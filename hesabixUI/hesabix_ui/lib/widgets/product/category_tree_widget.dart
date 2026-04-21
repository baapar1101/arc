import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import '../../utils/responsive_helper.dart';

class CategoryNode {
  final int id;
  final int? parentId;
  final String label;
  final Map<String, String> translations;
  final List<CategoryNode> children;
  final String? description;
  final int sortOrder;

  CategoryNode({
    required this.id,
    this.parentId,
    required this.label,
    required this.translations,
    required this.children,
    this.description,
    this.sortOrder = 0,
  });

  factory CategoryNode.fromMap(Map<String, dynamic> map) {
    final childrenList = (map['children'] as List<dynamic>?) ?? [];
    return CategoryNode(
      id: (map['id'] as num?)?.toInt() ?? 0,
      parentId: (map['parent_id'] as num?)?.toInt(),
      label: map['label']?.toString() ?? '',
      translations: Map<String, String>.from(map['translations'] ?? {}),
      description: map['description']?.toString(),
      sortOrder: (map['sort_order'] as num?)?.toInt() ?? 0,
      children: childrenList.map((e) => CategoryNode.fromMap(Map<String, dynamic>.from(e as Map))).toList(),
    );
  }
}

class CategoryTreeWidget extends StatefulWidget {
  final List<CategoryNode> categories;
  final int? selectedCategoryId;
  final ValueChanged<int?> onCategorySelected;
  final bool showAllOption;

  const CategoryTreeWidget({
    super.key,
    required this.categories,
    this.selectedCategoryId,
    required this.onCategorySelected,
    this.showAllOption = true,
  });

  @override
  State<CategoryTreeWidget> createState() => _CategoryTreeWidgetState();
}

class _CategoryTreeWidgetState extends State<CategoryTreeWidget> {
  final Set<int> _expandedCategories = {};

  @override
  void initState() {
    super.initState();
    // اگر یک دسته انتخاب شده، مسیر آن را expand کن
    if (widget.selectedCategoryId != null) {
      _expandPathToCategory(widget.categories, widget.selectedCategoryId!);
    }
  }

  void _expandPathToCategory(List<CategoryNode> nodes, int targetId) {
    for (final node in nodes) {
      if (node.id == targetId) {
        // پیدا شد، حالا باید parent ها را expand کن
        _expandParents(node.parentId, widget.categories);
        return;
      }
      if (node.children.isNotEmpty) {
        _expandPathToCategory(node.children, targetId);
      }
    }
  }

  void _expandParents(int? parentId, List<CategoryNode> nodes) {
    if (parentId == null) return;
    for (final node in nodes) {
      if (node.id == parentId) {
        _expandedCategories.add(node.id);
        _expandParents(node.parentId, widget.categories);
        return;
      }
      if (node.children.isNotEmpty) {
        _expandParents(parentId, node.children);
      }
    }
  }

  void _toggleExpand(int categoryId) {
    setState(() {
      if (_expandedCategories.contains(categoryId)) {
        _expandedCategories.remove(categoryId);
      } else {
        _expandedCategories.add(categoryId);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final t = AppLocalizations.of(context);

    return ListView(
      children: [
        if (widget.showAllOption)
          _buildCategoryItem(
            context: context,
            theme: theme,
            colorScheme: colorScheme,
            label: t.categoryTreeAllCategoriesOption,
            icon: Icons.category_outlined,
            isSelected: widget.selectedCategoryId == null,
            onTap: () => widget.onCategorySelected(null),
            hasChildren: false,
            isExpanded: false,
            onToggleExpand: null,
            level: 0,
          ),
        ...widget.categories.map((node) => _buildCategoryNode(
              context: context,
              theme: theme,
              colorScheme: colorScheme,
              node: node,
              level: 0,
            )),
      ],
    );
  }

  Widget _buildCategoryNode({
    required BuildContext context,
    required ThemeData theme,
    required ColorScheme colorScheme,
    required CategoryNode node,
    required int level,
  }) {
    final hasChildren = node.children.isNotEmpty;
    final isExpanded = _expandedCategories.contains(node.id);
    final isSelected = widget.selectedCategoryId == node.id;

    return Column(
      children: [
        _buildCategoryItem(
          context: context,
          theme: theme,
          colorScheme: colorScheme,
          label: node.label,
          icon: hasChildren ? Icons.folder : Icons.category,
          isSelected: isSelected,
          onTap: () => widget.onCategorySelected(node.id),
          hasChildren: hasChildren,
          isExpanded: isExpanded,
          onToggleExpand: hasChildren ? () => _toggleExpand(node.id) : null,
          level: level,
        ),
        if (hasChildren && isExpanded)
          ...node.children.map((child) => _buildCategoryNode(
                context: context,
                theme: theme,
                colorScheme: colorScheme,
                node: child,
                level: level + 1,
              )),
      ],
    );
  }

  Widget _buildCategoryItem({
    required BuildContext context,
    required ThemeData theme,
    required ColorScheme colorScheme,
    required String label,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
    required bool hasChildren,
    required bool isExpanded,
    required VoidCallback? onToggleExpand,
    required int level,
  }) {
    final step = ResponsiveHelper.isMobile(context) ? 18.0 : 24.0;
    final basePad = ResponsiveHelper.getPadding(context);
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.only(
          left: basePad + (level * step),
          right: basePad,
          top: 8,
          bottom: 8,
        ),
        decoration: BoxDecoration(
          color: isSelected ? colorScheme.primaryContainer : null,
          border: Border(
            right: BorderSide(
              color: isSelected ? colorScheme.primary : Colors.transparent,
              width: 3,
            ),
          ),
        ),
        child: Row(
          children: [
            if (hasChildren)
              IconButton(
                icon: Icon(
                  isExpanded ? Icons.expand_less : Icons.expand_more,
                  size: 20,
                  color: colorScheme.onSurface.withValues(alpha: 0.6),
                ),
                onPressed: onToggleExpand,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              )
            else
              SizedBox(width: 20),
            const SizedBox(width: 8),
            Icon(
              icon,
              size: 18,
              color: isSelected
                  ? colorScheme.onPrimaryContainer
                  : colorScheme.onSurface.withValues(alpha: 0.7),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  color: isSelected
                      ? colorScheme.onPrimaryContainer
                      : colorScheme.onSurface,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Helper function برای جمع‌آوری تمام IDهای زیردسته‌های یک دسته‌بندی
List<int> getAllCategoryIds(CategoryNode node) {
  final List<int> ids = [node.id];
  for (final child in node.children) {
    ids.addAll(getAllCategoryIds(child));
  }
  return ids;
}

/// Helper function برای پیدا کردن یک node در درخت بر اساس ID
CategoryNode? findCategoryNode(List<CategoryNode> nodes, int categoryId) {
  for (final node in nodes) {
    if (node.id == categoryId) {
      return node;
    }
    if (node.children.isNotEmpty) {
      final found = findCategoryNode(node.children, categoryId);
      if (found != null) return found;
    }
  }
  return null;
}


