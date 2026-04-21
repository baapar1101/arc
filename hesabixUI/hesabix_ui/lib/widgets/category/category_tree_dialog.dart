import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import '../../services/category_service.dart';
import '../../services/product_service.dart';
import '../../core/api_client.dart';
import '../../core/auth_store.dart';
import '../../utils/number_formatters.dart';
import '../../utils/responsive_helper.dart';
import 'category_picker_field.dart';
import '../../utils/snackbar_helper.dart';

class CategoryTreeDialog extends StatefulWidget {
  final int businessId;
  final AuthStore authStore;

  const CategoryTreeDialog({super.key, required this.businessId, required this.authStore});

  @override
  State<CategoryTreeDialog> createState() => _CategoryTreeDialogState();
}

class _CategoryTreeDialogState extends State<CategoryTreeDialog> {
  late final CategoryService _service;
  late final ProductService _productService;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _tree = const <Map<String, dynamic>>[];
  final Set<int> _expandedNodes = <int>{};
  bool _showProducts = false;
  int? _selectedCategoryForProducts;
  bool _loadingProducts = false;
  List<Map<String, dynamic>> _categoryProducts = const <Map<String, dynamic>>[];

  @override
  void initState() {
    super.initState();
    _service = CategoryService(ApiClient());
    _productService = ProductService();
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

  Set<int> _collectAllNodeIdsWithChildren(List<Map<String, dynamic>> nodes) {
    final Set<int> ids = {};
    for (final node in nodes) {
      final id = node['id'] as int?;
      if (id == null) continue;

      final children = (node['children'] as List?)?.cast<dynamic>().map((e) => Map<String, dynamic>.from(e as Map)).toList() ??
          const <Map<String, dynamic>>[];

      if (children.isNotEmpty) {
        ids.add(id);
        ids.addAll(_collectAllNodeIdsWithChildren(children));
      }
    }
    return ids;
  }

  void _expandAll() {
    setState(() {
      _expandedNodes.addAll(_collectAllNodeIdsWithChildren(_tree));
    });
  }

  void _collapseAll() {
    setState(() {
      _expandedNodes.clear();
    });
  }

  bool get _canAdd => widget.authStore.hasBusinessPermission('categories', 'add');
  bool get _canEdit => widget.authStore.hasBusinessPermission('categories', 'edit');
  bool get _canDelete => widget.authStore.hasBusinessPermission('categories', 'delete');

  double get _indentStep => ResponsiveHelper.isMobile(context) ? 16.0 : 24.0;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final isMobile = ResponsiveHelper.isMobile(context);
    final padding = ResponsiveHelper.getPadding(context);

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_selectedCategoryForProducts == null) _buildModeSelector(context, t, padding),
        Expanded(child: _buildBody(t)),
      ],
    );

    if (isMobile) {
      return Dialog(
        insetPadding: EdgeInsets.zero,
        backgroundColor: theme.colorScheme.surface,
        clipBehavior: Clip.antiAlias,
        child: Scaffold(
          backgroundColor: theme.colorScheme.surface,
          appBar: AppBar(
            centerTitle: false,
            titleSpacing: 8,
            title: Text(
              t.categoriesDialogTitle,
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
            ),
            leading: IconButton(
              icon: const Icon(Icons.close_rounded),
              tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
              onPressed: () => Navigator.of(context).pop(),
            ),
            actions: [
              if (_canAdd)
                IconButton.filledTonal(
                  icon: const Icon(Icons.add_rounded),
                  tooltip: t.addCategory,
                  onPressed: () => _showEditDialog(isRoot: true),
                ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert_rounded),
                tooltip: t.categoryTreeActionsMenuTooltip,
                onSelected: (value) {
                  switch (value) {
                    case 'expand':
                      _expandAll();
                      break;
                    case 'collapse':
                      _collapseAll();
                      break;
                    case 'add':
                      if (_canAdd) _showEditDialog(isRoot: true);
                      break;
                  }
                },
                itemBuilder: (ctx) => [
                  PopupMenuItem(
                    value: 'expand',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.unfold_more_rounded),
                      title: Text(t.expandAllCategories),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'collapse',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.unfold_less_rounded),
                      title: Text(t.collapseAllCategories),
                    ),
                  ),
                  if (_canAdd)
                    PopupMenuItem(
                      value: 'add',
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.add_rounded),
                        title: Text(t.addCategory),
                      ),
                    ),
                ],
              ),
            ],
          ),
          body: body,
        ),
      );
    }

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
      child: Material(
        elevation: 6,
        shadowColor: theme.shadowColor.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        color: theme.colorScheme.surface,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 720,
            maxHeight: MediaQuery.sizeOf(context).height * 0.92,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(20, 16, 12, 8),
                child: Row(
                  children: [
                    Icon(Icons.category_rounded, color: theme.colorScheme.primary, size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        t.categoriesDialogTitle,
                        style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                    IconButton(
                      tooltip: t.expandAllCategories,
                      onPressed: _expandAll,
                      icon: const Icon(Icons.unfold_more_rounded),
                    ),
                    IconButton(
                      tooltip: t.collapseAllCategories,
                      onPressed: _collapseAll,
                      icon: const Icon(Icons.unfold_less_rounded),
                    ),
                    if (_canAdd)
                      IconButton.filledTonal(
                        tooltip: t.addCategory,
                        onPressed: () => _showEditDialog(isRoot: true),
                        icon: const Icon(Icons.add_rounded),
                      ),
                    IconButton(
                      tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
              if (_selectedCategoryForProducts == null) _buildModeSelector(context, t, 20),
              Expanded(child: _buildBody(t)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModeSelector(BuildContext context, AppLocalizations t, double horizontalPadding) {
    return Padding(
      padding: EdgeInsets.fromLTRB(horizontalPadding, 12, horizontalPadding, 8),
      child: SegmentedButton<int>(
        showSelectedIcon: false,
        style: ButtonStyle(
          visualDensity: VisualDensity.comfortable,
          padding: WidgetStateProperty.all(const EdgeInsets.symmetric(horizontal: 12, vertical: 12)),
        ),
        segments: <ButtonSegment<int>>[
          ButtonSegment<int>(
            value: 0,
            label: Text(t.categories),
            icon: const Icon(Icons.account_tree_outlined, size: 18),
          ),
          ButtonSegment<int>(
            value: 1,
            label: Text(t.products),
            icon: const Icon(Icons.inventory_2_outlined, size: 18),
          ),
        ],
        selected: <int>{_showProducts ? 1 : 0},
        onSelectionChanged: (Set<int> next) {
          final v = next.first;
          setState(() {
            _showProducts = v == 1;
            if (!_showProducts) {
              _selectedCategoryForProducts = null;
              _categoryProducts = const [];
            }
          });
        },
      ),
    );
  }

  Widget _buildBody(AppLocalizations t) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!, textAlign: TextAlign.center),
        ),
      );
    }

    if (_showProducts && _selectedCategoryForProducts != null) {
      return _buildProductsList(t);
    }

    return RefreshIndicator(
      onRefresh: _fetch,
      child: ListView(
        padding: EdgeInsets.symmetric(
          vertical: 8,
          horizontal: ResponsiveHelper.getPadding(context),
        ),
        physics: const AlwaysScrollableScrollPhysics(),
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
      final children = (item['children'] as List?)?.cast<dynamic>().map((e) => Map<String, dynamic>.from(e as Map)).toList() ??
          const <Map<String, dynamic>>[];
      final isExpanded = id != null && _expandedNodes.contains(id);
      final hasChildren = children.isNotEmpty;

      widgets.add(
        _CategoryTreeNodeWidget(
          label: label,
          description: description,
          level: level,
          indentStep: _indentStep,
          isExpanded: isExpanded,
          hasChildren: hasChildren,
          showProductsMode: _showProducts,
          canAdd: _canAdd,
          canEdit: _canEdit,
          canDelete: _canDelete,
          onToggleExpand: hasChildren
              ? () {
                  setState(() {
                    if (isExpanded) {
                      _expandedNodes.remove(id);
                    } else {
                      _expandedNodes.add(id!);
                    }
                  });
                }
              : null,
          onPrimaryContentTap: () {
            if (_showProducts) {
              _loadCategoryProducts(id);
              return;
            }
            if (hasChildren) {
              setState(() {
                if (isExpanded) {
                  _expandedNodes.remove(id);
                } else {
                  _expandedNodes.add(id!);
                }
              });
            } else if (_canAdd || _canEdit || _canDelete) {
              _openNodeActionsSheet(t, item);
            }
          },
          onMorePressed: () => _openNodeActionsSheet(t, item),
          t: t,
        ),
      );

      if (isExpanded && hasChildren) {
        widgets.addAll(_buildTreeNodes(children, t, level + 1));
      }
    }

    return widgets;
  }

  void _openNodeActionsSheet(AppLocalizations t, Map<String, dynamic> item) {
    final id = item['id'] as int?;
    final label = (item['label'] ?? item['title'] ?? item['name'] ?? '').toString();
    final description = item['description'] as String?;
    final sortOrder = (item['sort_order'] as num?)?.toInt();
    final currentParentId = (item['parent_id'] as num?)?.toInt();

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) {
        final theme = Theme.of(sheetCtx);
        final bottomInset = MediaQuery.paddingOf(sheetCtx).bottom;
        return SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: EdgeInsets.only(left: 16, right: 16, bottom: bottomInset + 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: theme.colorScheme.primaryContainer,
                        foregroundColor: theme.colorScheme.onPrimaryContainer,
                        child: const Icon(Icons.category_rounded),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              label,
                              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                            ),
                            if (description != null && description.isNotEmpty)
                              Text(
                                description,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (_showProducts && id != null)
                    ListTile(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      tileColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
                      leading: Icon(Icons.inventory_2_outlined, color: theme.colorScheme.primary),
                      title: Text(t.categoryTreeShowProductsInCategory),
                      trailing: const Icon(Icons.chevron_left_rounded),
                      onTap: () {
                        Navigator.pop(sheetCtx);
                        _loadCategoryProducts(id);
                      },
                    ),
                  if (_canAdd && id != null)
                    ListTile(
                      leading: const Icon(Icons.add_circle_outline_rounded),
                      title: Text(t.addChildCategory),
                      onTap: () {
                        Navigator.pop(sheetCtx);
                        _showEditDialog(parentId: id);
                      },
                    ),
                  if (_canEdit && id != null)
                    ListTile(
                      leading: const Icon(Icons.edit_outlined),
                      title: Text(t.renameCategory),
                      onTap: () {
                        Navigator.pop(sheetCtx);
                        _showEditDialog(
                          categoryId: id,
                          initialLabel: label,
                          initialDescription: description,
                          initialSortOrder: sortOrder,
                          initialParentId: currentParentId,
                        );
                      },
                    ),
                  if (_canDelete && id != null)
                    ListTile(
                      leading: Icon(Icons.delete_outline_rounded, color: theme.colorScheme.error),
                      title: Text(t.deleteCategory, style: TextStyle(color: theme.colorScheme.error)),
                      onTap: () {
                        Navigator.pop(sheetCtx);
                        _confirmDelete(id);
                      },
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  List<Map<String, dynamic>> _filterTreeExcludingCategory(
    List<Map<String, dynamic>> tree,
    int excludeId,
  ) {
    List<Map<String, dynamic>> result = [];
    for (final node in tree) {
      final id = (node['id'] as num?)?.toInt();
      if (id == excludeId) {
        continue;
      }
      final children = (node['children'] as List?)?.cast<dynamic>().map((e) => Map<String, dynamic>.from(e as Map)).toList() ??
          const <Map<String, dynamic>>[];
      final filteredChildren = _filterTreeExcludingCategory(children, excludeId);
      final newNode = Map<String, dynamic>.from(node);
      newNode['children'] = filteredChildren;
      result.add(newNode);
    }
    return result;
  }

  void _expandToNode(int targetId) {
    bool findAndExpand(List<Map<String, dynamic>> nodes, int targetId, List<int> path) {
      for (final node in nodes) {
        final id = node['id'] as int?;
        if (id == null) continue;

        final currentPath = [...path, id];

        if (id == targetId) {
          setState(() {
            for (final pathId in currentPath) {
              _expandedNodes.add(pathId);
            }
          });
          return true;
        }

        final children = (node['children'] as List?)?.cast<dynamic>().map((e) => Map<String, dynamic>.from(e as Map)).toList() ??
            const <Map<String, dynamic>>[];

        if (children.isNotEmpty) {
          if (findAndExpand(children, targetId, currentPath)) {
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

  Map<String, dynamic>? findNode(List<Map<String, dynamic>> nodes, int targetId) {
    for (final node in nodes) {
      if ((node['id'] as int?) == targetId) {
        return node;
      }
      final children = (node['children'] as List?)?.cast<dynamic>().map((e) => Map<String, dynamic>.from(e as Map)).toList() ??
          const <Map<String, dynamic>>[];
      final found = findNode(children, targetId);
      if (found != null) return found;
    }
    return null;
  }

  Set<int> _collectAllDescendantIds(Map<String, dynamic> node) {
    final Set<int> ids = {};
    final id = node['id'] as int?;
    if (id != null) {
      ids.add(id);
    }
    final children = (node['children'] as List?)?.cast<dynamic>().map((e) => Map<String, dynamic>.from(e as Map)).toList() ??
        const <Map<String, dynamic>>[];
    for (final child in children) {
      ids.addAll(_collectAllDescendantIds(child));
    }
    return ids;
  }

  Future<void> _loadCategoryProducts(int? categoryId) async {
    if (categoryId == null) return;

    setState(() {
      _selectedCategoryForProducts = categoryId;
      _loadingProducts = true;
      _categoryProducts = const [];
    });

    try {
      final node = findNode(_tree, categoryId);
      final categoryIds = <int>[categoryId];
      if (node != null) {
        final allDescendantIds = _collectAllDescendantIds(node);
        categoryIds.addAll(allDescendantIds);
      }

      final filters = [
        {
          'property': 'category_id',
          'operator': 'in',
          'value': categoryIds.map((id) => id.toString()).toList(),
        },
      ];

      final products = await _productService.searchProducts(
        businessId: widget.businessId,
        filters: filters,
        limit: 1000,
        skip: 0,
      );

      if (mounted) {
        setState(() {
          _categoryProducts = products;
          _loadingProducts = false;
        });
      }
    } catch (e) {
      if (mounted) {
        final loc = AppLocalizations.of(context);
        setState(() {
          _loadingProducts = false;
          _error = loc.categoryLoadProductsError(e.toString());
        });
      }
    }
  }

  Widget _buildProductsList(AppLocalizations t) {
    final theme = Theme.of(context);
    final isMobile = ResponsiveHelper.isMobile(context);
    String categoryName = t.category;
    final node = findNode(_tree, _selectedCategoryForProducts!);
    if (node != null) {
      categoryName = (node['label'] ?? node['title'] ?? node['name'] ?? t.category).toString();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          elevation: 0,
          color: theme.colorScheme.surfaceContainerHigh.withValues(alpha: 0.65),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: isMobile ? 4 : 8, vertical: 4),
            child: Row(
              children: [
                IconButton(
                  style: IconButton.styleFrom(
                    foregroundColor: theme.colorScheme.primary,
                  ),
                  icon: const Icon(Icons.arrow_forward_rounded),
                  onPressed: () {
                    setState(() {
                      _selectedCategoryForProducts = null;
                      _categoryProducts = const [];
                    });
                  },
                  tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        categoryName,
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        '${_categoryProducts.length} ${t.products}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: _loadingProducts
              ? const Center(child: CircularProgressIndicator())
              : _categoryProducts.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.inventory_2_outlined,
                            size: 64,
                            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.45),
                          ),
                          const SizedBox(height: 16),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 32),
                            child: Text(
                              t.categoryTreeNoProductsInCategory,
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodyLarge?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: EdgeInsets.fromLTRB(
                        ResponsiveHelper.getPadding(context),
                        12,
                        ResponsiveHelper.getPadding(context),
                        24,
                      ),
                      itemCount: _categoryProducts.length,
                      itemBuilder: (context, index) {
                        final product = _categoryProducts[index];
                        final code = product['code']?.toString() ?? '-';
                        final name = product['name']?.toString() ?? '-';
                        final itemType = product['item_type']?.toString() ?? '-';
                        final salesPrice = product['base_sales_price'];
                        final purchasePrice = product['base_purchase_price'];
                        final categoryNameProduct = product['category_name']?.toString();

                        return Card(
                          elevation: 0,
                          margin: const EdgeInsets.only(bottom: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                            side: BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                CircleAvatar(
                                  radius: 22,
                                  backgroundColor: theme.colorScheme.primaryContainer,
                                  child: Icon(
                                    Icons.inventory_2_rounded,
                                    color: theme.colorScheme.onPrimaryContainer,
                                    size: 22,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        name,
                                        style: theme.textTheme.titleSmall?.copyWith(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Wrap(
                                        spacing: 8,
                                        runSpacing: 4,
                                        children: [
                                          _ProductMetaChip(
                                            icon: Icons.tag_rounded,
                                            label: code,
                                            monospace: true,
                                          ),
                                          _ProductMetaChip(
                                            icon: Icons.label_outline_rounded,
                                            label: itemType,
                                          ),
                                          if (categoryNameProduct != null && categoryNameProduct.isNotEmpty)
                                            _ProductMetaChip(
                                              icon: Icons.category_outlined,
                                              label: categoryNameProduct,
                                            ),
                                        ],
                                      ),
                                      if (salesPrice != null || purchasePrice != null) ...[
                                        const SizedBox(height: 8),
                                        Wrap(
                                          spacing: 12,
                                          runSpacing: 4,
                                          children: [
                                            if (salesPrice != null)
                                              Text(
                                                '${t.sales}: ${_formatNumber(salesPrice)}',
                                                style: theme.textTheme.bodySmall?.copyWith(
                                                  color: theme.colorScheme.primary,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            if (purchasePrice != null)
                                              Text(
                                                '${t.buy}: ${_formatNumber(purchasePrice)}',
                                                style: theme.textTheme.bodySmall?.copyWith(
                                                  color: theme.colorScheme.tertiary,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                          ],
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  String _formatNumber(dynamic value) {
    if (value == null) return '-';
    if (value is num) {
      return formatWithThousands(value, decimalPlaces: 0);
    }
    return value.toString();
  }

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
    int? selectedParentId = categoryId != null ? initialParentId : (isRoot ? null : parentId);
    final isMobile = ResponsiveHelper.isMobile(context);

    void disposeCtrls() {
      labelCtrl.dispose();
      descriptionCtrl.dispose();
      sortOrderCtrl.dispose();
    }

    void submitForm(BuildContext ctx) {
      if (formKey.currentState?.validate() != true) return;
      final sortOrder = categoryId != null ? int.tryParse(sortOrderCtrl.text.trim()) : null;
      Navigator.pop(ctx, {
        'label': labelCtrl.text.trim(),
        'description': descriptionCtrl.text.trim().isEmpty ? null : descriptionCtrl.text.trim(),
        'sort_order': sortOrder,
        'parent_id': categoryId != null ? selectedParentId : null,
      });
    }

    Widget formFields(BuildContext ctx) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: labelCtrl,
            decoration: InputDecoration(
              labelText: t.categoryName,
              hintText: t.categoryNameHint,
              prefixIcon: const Icon(Icons.category_outlined),
              border: const OutlineInputBorder(),
              filled: true,
              fillColor: Theme.of(ctx).colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
            ),
            textInputAction: TextInputAction.next,
            autofocus: !isMobile,
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
            decoration: InputDecoration(
              labelText: t.description,
              hintText: t.categoryDescriptionHint,
              prefixIcon: const Icon(Icons.description_outlined),
              border: const OutlineInputBorder(),
              filled: true,
              fillColor: Theme.of(ctx).colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
            ),
            maxLines: 3,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 16),
          if (categoryId != null)
            TextFormField(
              controller: sortOrderCtrl,
              decoration: InputDecoration(
                labelText: t.categorySortOrderLabel,
                hintText: t.categorySortOrderHint,
                prefixIcon: const Icon(Icons.sort_rounded),
                border: const OutlineInputBorder(),
                filled: true,
                fillColor: Theme.of(ctx).colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
              ),
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.next,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return t.categorySortOrderRequired;
                }
                final intValue = int.tryParse(value.trim());
                if (intValue == null) {
                  return t.categorySortOrderInvalidNumber;
                }
                return null;
              },
            ),
          if (categoryId != null) const SizedBox(height: 16),
          if (categoryId != null)
            CategoryPickerField(
              businessId: widget.businessId,
              categoriesTree: _filterTreeExcludingCategory(_tree, categoryId),
              initialValue: selectedParentId,
              onChanged: (value) {
                selectedParentId = value;
              },
              label: t.categoryParentFieldLabel,
            ),
        ],
      );
    }

    Map<String, dynamic>? result;
    try {
      if (isMobile) {
        result = await showModalBottomSheet<Map<String, dynamic>?>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        backgroundColor: Theme.of(context).colorScheme.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (ctx) {
          final bottomViewInset = MediaQuery.viewInsetsOf(ctx).bottom;
          final padBottom = MediaQuery.paddingOf(ctx).bottom;
          return Padding(
            padding: EdgeInsets.only(bottom: bottomViewInset),
            child: SingleChildScrollView(
              child: Padding(
                padding: EdgeInsets.fromLTRB(20, 8, 20, 20 + padBottom),
                child: Form(
                  key: formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Icon(
                            categoryId == null ? Icons.add_circle_outline_rounded : Icons.edit_outlined,
                            color: Theme.of(ctx).colorScheme.primary,
                            size: 28,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              categoryId == null ? t.createCategory : t.updateCategory,
                              style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(ctx, null),
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      formFields(ctx),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.pop(ctx, null),
                              child: Text(t.cancel),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: FilledButton.icon(
                              onPressed: () => submitForm(ctx),
                              icon: Icon(categoryId == null ? Icons.add_rounded : Icons.save_rounded),
                              label: Text(categoryId == null ? t.createCategory : t.updateCategory),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      );
      } else {
        result = await showDialog<Map<String, dynamic>?>(
        context: context,
        builder: (ctx) => Dialog(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 500,
              maxHeight: MediaQuery.of(ctx).size.height * 0.85,
            ),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Icon(
                            categoryId == null ? Icons.add_circle_outline : Icons.edit_outlined,
                            color: Theme.of(ctx).colorScheme.primary,
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
                      formFields(ctx),
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, null),
                            child: Text(t.cancel),
                          ),
                          const SizedBox(width: 8),
                          FilledButton.icon(
                            onPressed: () => submitForm(ctx),
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
      }
    } finally {
      disposeCtrls();
    }

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

      if (newCategoryId != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _expandToNode(newCategoryId!);
        });
      }
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(context, message: t.operationFailed);
      }
    }
  }
}

class _ProductMetaChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool monospace;

  const _ProductMetaChip({
    required this.icon,
    required this.label,
    this.monospace = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(8),
      ),
        child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 4),
          Directionality(
            textDirection: monospace ? TextDirection.ltr : Directionality.of(context),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                fontFamily: monospace ? 'monospace' : null,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryTreeNodeWidget extends StatelessWidget {
  final String label;
  final String? description;
  final int level;
  final double indentStep;
  final bool isExpanded;
  final bool hasChildren;
  final bool showProductsMode;
  final bool canAdd;
  final bool canEdit;
  final bool canDelete;
  final VoidCallback? onToggleExpand;
  final VoidCallback onPrimaryContentTap;
  final VoidCallback onMorePressed;
  final AppLocalizations t;

  const _CategoryTreeNodeWidget({
    required this.label,
    this.description,
    required this.level,
    required this.indentStep,
    required this.isExpanded,
    required this.hasChildren,
    required this.showProductsMode,
    required this.canAdd,
    required this.canEdit,
    required this.canDelete,
    this.onToggleExpand,
    required this.onPrimaryContentTap,
    required this.onMorePressed,
    required this.t,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final indent = level * indentStep;
    final lineColor = theme.colorScheme.outline.withValues(alpha: 0.28);
    final showMore = canAdd || canEdit || canDelete || showProductsMode;

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Stack(
        children: [
          if (level > 0)
            Positioned(
              right: indent - indentStep * 0.5,
              top: 0,
              bottom: 0,
              child: Container(
                width: 1,
                color: lineColor,
              ),
            ),
          Material(
            color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
            borderRadius: BorderRadius.circular(12),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onPrimaryContentTap,
              child: Padding(
                padding: EdgeInsets.only(
                  right: indent + 8,
                  left: 4,
                  top: 6,
                  bottom: 6,
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 36,
                      child: hasChildren
                          ? IconButton(
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                              iconSize: 22,
                              onPressed: onToggleExpand,
                              icon: AnimatedRotation(
                                turns: isExpanded ? 0.25 : 0,
                                duration: const Duration(milliseconds: 200),
                                curve: Curves.easeOutCubic,
                                child: Icon(
                                  Icons.chevron_left_rounded,
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                            )
                          : const SizedBox(width: 8),
                    ),
                    Icon(
                      hasChildren ? Icons.folder_rounded : Icons.category_rounded,
                      size: 22,
                      color: hasChildren ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            label,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              fontWeight: hasChildren ? FontWeight.w600 : FontWeight.w500,
                            ),
                          ),
                          if (description != null && description!.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
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
                    if (showMore)
                      IconButton(
                        icon: const Icon(Icons.more_vert_rounded),
                        tooltip: t.categoryTreeMoreActionsTooltip,
                        onPressed: onMorePressed,
                        style: IconButton.styleFrom(
                          foregroundColor: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
