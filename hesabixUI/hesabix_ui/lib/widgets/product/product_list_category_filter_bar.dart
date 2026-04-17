import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

import '../../core/api_client.dart';
import '../../services/category_service.dart';
import '../../utils/responsive_helper.dart';
import 'category_tree_widget.dart';

/// نشانۀ لغو انتخاب در دیالوگ (متمایز از «همه» که [null] برمی‌گرداند)
const Object _kCategoryPickerDismissed = Object();

/// نوار فیلتر سریع دسته بالای لیست کالاها: چیپ ریشه‌ها، زیردسته‌ها، مسیر، درخت کامل + جستجو
class ProductListCategoryFilterBar extends StatefulWidget {
  final int businessId;
  final List<CategoryNode> categories;
  final bool loading;
  final int? selectedCategoryId;
  final ValueChanged<int?> onCategoryChanged;

  const ProductListCategoryFilterBar({
    super.key,
    required this.businessId,
    required this.categories,
    required this.loading,
    required this.selectedCategoryId,
    required this.onCategoryChanged,
  });

  @override
  State<ProductListCategoryFilterBar> createState() => _ProductListCategoryFilterBarState();
}

class _ProductListCategoryFilterBarState extends State<ProductListCategoryFilterBar> {
  final CategoryService _categoryService = CategoryService(ApiClient());

  List<CategoryNode>? _pathToId(List<CategoryNode> roots, int id) {
    List<CategoryNode>? walk(List<CategoryNode> nodes, List<CategoryNode> prefix) {
      for (final n in nodes) {
        if (n.id == id) return [...prefix, n];
        final sub = walk(n.children, [...prefix, n]);
        if (sub != null) return sub;
      }
      return null;
    }

    return walk(roots, const []);
  }

  CategoryNode? _selectedNode() {
    final id = widget.selectedCategoryId;
    if (id == null) return null;
    return findCategoryNode(widget.categories, id);
  }

  Future<void> _openFullPicker() async {
    final t = AppLocalizations.of(context);
    final isMobile = ResponsiveHelper.isMobile(context);
    final picked = await showDialog<Object?>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          clipBehavior: Clip.antiAlias,
          child: PopScope<Object?>(
            canPop: false,
            onPopInvokedWithResult: (bool didPop, Object? result) {
              if (didPop) return;
              Navigator.of(ctx).pop(_kCategoryPickerDismissed);
            },
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: isMobile ? double.infinity : 480,
                maxHeight: isMobile ? MediaQuery.sizeOf(ctx).height * 0.85 : 560,
              ),
              child: _CategoryBrowsePanel(
                businessId: widget.businessId,
                categories: widget.categories,
                categoryService: _categoryService,
                initialSelectedId: widget.selectedCategoryId,
                searchHint: t.search,
                title: t.categories,
                cancelLabel: t.cancel,
                allLabel: t.all,
              ),
            ),
          ),
        );
      },
    );
    if (!mounted) return;
    if (identical(picked, _kCategoryPickerDismissed)) {
      return;
    }
    widget.onCategoryChanged(picked as int?);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = AppLocalizations.of(context);
    final isFa = Localizations.localeOf(context).languageCode == 'fa';
    final browseAllLabel = isFa ? 'همه دسته‌ها' : 'All categories';
    final subLabel = isFa ? 'زیردسته' : 'Subcategories';

    if (!widget.loading && widget.categories.isEmpty) {
      return const SizedBox.shrink();
    }

    final selectedNode = _selectedNode();
    final path = widget.selectedCategoryId != null
        ? _pathToId(widget.categories, widget.selectedCategoryId!)
        : null;
    final childLevel = selectedNode?.children ?? const <CategoryNode>[];

    return Material(
      color: theme.colorScheme.surfaceContainerLow.withValues(alpha: 0.65),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.loading)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: const LinearProgressIndicator(minHeight: 3),
                ),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(Icons.filter_alt_outlined, size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  t.category,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        Padding(
                          padding: const EdgeInsetsDirectional.only(end: 6),
                          child: FilterChip(
                            label: Text(t.all),
                            selected: widget.selectedCategoryId == null,
                            onSelected: (_) => widget.onCategoryChanged(null),
                            showCheckmark: false,
                            avatar: Icon(
                              Icons.layers_outlined,
                              size: 18,
                              color: widget.selectedCategoryId == null
                                  ? theme.colorScheme.onSecondaryContainer
                                  : theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        for (final root in widget.categories)
                          Padding(
                            padding: const EdgeInsetsDirectional.only(end: 6),
                            child: FilterChip(
                              label: Text(
                                root.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              selected: widget.selectedCategoryId == root.id,
                              onSelected: (_) => widget.onCategoryChanged(root.id),
                              showCheckmark: false,
                            ),
                          ),
                        Padding(
                          padding: const EdgeInsetsDirectional.only(start: 4),
                          child: ActionChip(
                            avatar: const Icon(Icons.account_tree_outlined, size: 18),
                            label: Text(browseAllLabel),
                            onPressed: widget.loading ? null : _openFullPicker,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            if (path != null && path.isNotEmpty) ...[
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    TextButton(
                      onPressed: () => widget.onCategoryChanged(null),
                      child: Text(t.all),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Text(
                        '›',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    ),
                    for (var i = 0; i < path.length; i++) ...[
                      if (i < path.length - 1)
                        TextButton(
                          onPressed: () => widget.onCategoryChanged(path[i].id),
                          child: Text(
                            path[i].label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        )
                      else
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                          child: Text(
                            path[i].label,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      if (i < path.length - 1)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Text(
                            '›',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.outline,
                            ),
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ],
            if (childLevel.isNotEmpty) ...[
              const SizedBox(height: 6),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  subLabel,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final c in childLevel)
                      Padding(
                        padding: const EdgeInsetsDirectional.only(end: 6),
                        child: FilterChip(
                          label: Text(
                            c.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          selected: widget.selectedCategoryId == c.id,
                          onSelected: (_) => widget.onCategoryChanged(c.id),
                          showCheckmark: false,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CategoryBrowsePanel extends StatefulWidget {
  final int businessId;
  final List<CategoryNode> categories;
  final CategoryService categoryService;
  final int? initialSelectedId;
  final String title;
  final String searchHint;
  final String cancelLabel;
  final String allLabel;

  const _CategoryBrowsePanel({
    required this.businessId,
    required this.categories,
    required this.categoryService,
    required this.initialSelectedId,
    required this.title,
    required this.searchHint,
    required this.cancelLabel,
    required this.allLabel,
  });

  @override
  State<_CategoryBrowsePanel> createState() => _CategoryBrowsePanelState();
}

class _CategoryBrowsePanelState extends State<_CategoryBrowsePanel> {
  final TextEditingController _searchCtrl = TextEditingController();
  Timer? _debounce;
  String _query = '';
  bool _searchLoading = false;
  List<Map<String, dynamic>> _searchHits = [];

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _runSearch(String q) async {
    final trimmed = q.trim();
    if (trimmed.isEmpty) {
      if (mounted) {
        setState(() {
          _searchHits = [];
          _searchLoading = false;
        });
      }
      return;
    }
    setState(() => _searchLoading = true);
    try {
      final items = await widget.categoryService.searchCategories(
        businessId: widget.businessId,
        query: trimmed,
        limit: 80,
      );
      if (!mounted) return;
      setState(() {
        _searchHits = items;
        _searchLoading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _searchHits = [];
          _searchLoading = false;
        });
      }
    }
  }

  String _formatPath(dynamic path) {
    if (path is List) {
      final parts = path.map((e) => e?.toString() ?? '').where((s) => s.isNotEmpty).toList();
      return parts.join(' › ');
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  widget.title,
                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              IconButton(
                tooltip: widget.cancelLabel,
                onPressed: () => Navigator.of(context).pop(_kCategoryPickerDismissed),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              hintText: widget.searchHint,
              prefixIcon: const Icon(Icons.search),
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (v) {
              _debounce?.cancel();
              setState(() => _query = v);
              _debounce = Timer(const Duration(milliseconds: 350), () => _runSearch(v));
            },
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              FilledButton.tonalIcon(
                onPressed: () => Navigator.of(context).pop<int?>(null),
                icon: const Icon(Icons.clear_all_outlined, size: 18),
                label: Text(widget.allLabel),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: _query.trim().isEmpty
              ? CategoryTreeWidget(
                  categories: widget.categories,
                  selectedCategoryId: widget.initialSelectedId,
                  showAllOption: false,
                  onCategorySelected: (id) => Navigator.of(context).pop<int?>(id),
                )
              : _searchLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _searchHits.isEmpty
                      ? Center(
                          child: Text(
                            Localizations.localeOf(context).languageCode == 'fa'
                                ? 'دسته‌ای یافت نشد'
                                : 'No categories found',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          itemCount: _searchHits.length,
                          separatorBuilder: (context, _) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final row = _searchHits[index];
                            final id = (row['id'] as num?)?.toInt();
                            final label = row['label']?.toString() ?? '';
                            final pathStr = _formatPath(row['path']);
                            if (id == null) return const SizedBox.shrink();
                            return ListTile(
                              leading: const Icon(Icons.label_outline),
                              title: Text(label),
                              subtitle: pathStr.isEmpty ? null : Text(pathStr, maxLines: 2),
                              onTap: () => Navigator.of(context).pop<int?>(id),
                            );
                          },
                        ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}
