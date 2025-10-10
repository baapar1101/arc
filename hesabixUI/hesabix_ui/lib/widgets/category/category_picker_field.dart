import 'dart:async';
import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import '../../services/category_service.dart';
import '../../core/api_client.dart';

class CategoryPickerField extends FormField<int?> {
  CategoryPickerField({
    super.key,
    required this.businessId,
    required List<Map<String, dynamic>> categoriesTree,
    required ValueChanged<int?> onChanged,
    super.initialValue,
    String? label,
    super.validator,
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

  const _CategoryPickerDialog({
    required this.categoriesTree,
    required this.initialCategoryId,
    required this.businessId,
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

  @override
  void initState() {
    super.initState();
    _selectedId = widget.initialCategoryId;
    _service = CategoryService(ApiClient());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final useServer = _query.trim().length >= 3 || _countNodes(widget.categoriesTree) > 500;
    final filteredTree = useServer
        ? _resultsToTree(_serverResults)
        : (_query.isEmpty ? widget.categoriesTree : _filterTree(widget.categoriesTree, _query));
    return AlertDialog(
      title: Text(t.categories),
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
}

class _CategoryList extends StatelessWidget {
  final List<Map<String, dynamic>> tree;
  final int? selectedId;
  final ValueChanged<int?> onSelect;

  const _CategoryList({
    required this.tree,
    required this.selectedId,
    required this.onSelect,
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
        ),
        if (children.isNotEmpty)
          ...children.map((c) => _buildNode(context, c, depth + 1)),
      ],
    );
  }
}


