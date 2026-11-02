import 'dart:async';

import 'package:flutter/material.dart';

import '../../utils/responsive_helper.dart';

class OaSearchItem {
  final String id;
  final String title;
  final String? subtitle;
  final IconData? icon;
  final Object? payload;

  const OaSearchItem({
    required this.id,
    required this.title,
    this.subtitle,
    this.icon,
    this.payload,
  });
}

/// فیلد انتخاب با جست‌وجوی زنده — مناسب سازمان‌های بزرگ به‌جای Dropdown.
class OaSearchableField extends StatefulWidget {
  final String label;
  final String hint;
  final String? searchHint;
  final OaSearchItem? value;
  final Future<List<OaSearchItem>> Function(String query) onSearch;
  final ValueChanged<OaSearchItem?> onChanged;
  final bool enabled;
  final bool allowClear;
  final IconData prefixIcon;
  final String emptyText;
  final String? helperText;

  const OaSearchableField({
    super.key,
    required this.label,
    required this.onSearch,
    required this.onChanged,
    this.value,
    this.hint = '',
    this.searchHint,
    this.enabled = true,
    this.allowClear = true,
    this.prefixIcon = Icons.search,
    this.emptyText = '',
    this.helperText,
  });

  @override
  State<OaSearchableField> createState() => _OaSearchableFieldState();
}

class _OaSearchableFieldState extends State<OaSearchableField> {
  final LayerLink _link = LayerLink();
  final FocusNode _focus = FocusNode();
  OverlayEntry? _overlay;
  Timer? _debounce;
  int _seq = 0;
  List<OaSearchItem> _items = [];
  bool _loading = false;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) {
        Future.delayed(const Duration(milliseconds: 160), _removeOverlay);
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _removeOverlay();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _runSearch(String query) async {
    final seq = ++_seq;
    setState(() {
      _loading = true;
      _query = query;
    });
    try {
      final items = await widget.onSearch(query);
      if (!mounted || seq != _seq) return;
      setState(() {
        _items = items;
        _loading = false;
      });
      _overlay?.markNeedsBuild();
    } catch (_) {
      if (!mounted || seq != _seq) return;
      setState(() {
        _items = [];
        _loading = false;
      });
      _overlay?.markNeedsBuild();
    }
  }

  void _scheduleSearch(String query) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 220), () => _runSearch(query));
  }

  void _removeOverlay() {
    _overlay?.remove();
    _overlay = null;
  }

  Future<void> _openPicker() async {
    if (!widget.enabled) return;
    final compact = ResponsiveHelper.isMobile(context) || ResponsiveHelper.isShellCompactWidth(context);
    await _runSearch(_query);
    if (!mounted) return;
    if (compact) {
      await _openSheet();
    } else {
      _showOverlay();
    }
  }

  Future<void> _openSheet() async {
    final selected = await showModalBottomSheet<OaSearchItem>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => _OaSearchSheet(
        label: widget.label,
        hint: widget.searchHint ?? widget.hint,
        emptyText: widget.emptyText,
        initialQuery: _query,
        initialItems: _items,
        onSearch: widget.onSearch,
      ),
    );
    if (selected != null) widget.onChanged(selected);
  }

  void _showOverlay() {
    _removeOverlay();
    final box = context.findRenderObject() as RenderBox?;
    final width = box?.size.width ?? 320;
    _overlay = OverlayEntry(
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return Positioned.fill(
          child: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: _removeOverlay,
                ),
              ),
              CompositedTransformFollower(
                  link: _link,
                  showWhenUnlinked: false,
                  offset: const Offset(0, 56),
                  child: Material(
                    elevation: 8,
                    borderRadius: BorderRadius.circular(12),
                    color: theme.colorScheme.surface,
                    child: SizedBox(
                      width: width,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 420),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                              child: TextField(
                                autofocus: true,
                                focusNode: _focus,
                                decoration: InputDecoration(
                                  hintText: widget.searchHint ?? widget.hint,
                                  prefixIcon: const Icon(Icons.search),
                                  border: const OutlineInputBorder(),
                                  isDense: true,
                                ),
                                onChanged: _scheduleSearch,
                              ),
                            ),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxHeight: 300),
                              child: _OaSearchResults(
                                items: _items,
                                loading: _loading,
                                emptyText: widget.emptyText,
                                onPick: (item) {
                                  widget.onChanged(item);
                                  _removeOverlay();
                                  _focus.unfocus();
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ),
            ],
          ),
        );
      },
    );
    Overlay.of(context).insert(_overlay!);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = widget.value;
    return CompositedTransformTarget(
      link: _link,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: widget.label,
          helperText: widget.helperText,
          prefixIcon: Icon(widget.prefixIcon),
          suffixIcon: selected != null && widget.allowClear && widget.enabled
              ? IconButton(
                  tooltip: MaterialLocalizations.of(context).deleteButtonTooltip,
                  icon: const Icon(Icons.close),
                  onPressed: () => widget.onChanged(null),
                )
              : Icon(Icons.expand_more, color: theme.colorScheme.onSurfaceVariant),
          border: const OutlineInputBorder(),
          enabled: widget.enabled,
        ),
        child: InkWell(
          onTap: widget.enabled ? _openPicker : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: selected == null
                ? Text(
                    widget.hint,
                    style: theme.textTheme.bodyLarge?.copyWith(color: theme.hintColor),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(selected.title, style: theme.textTheme.bodyLarge),
                      if ((selected.subtitle ?? '').isNotEmpty)
                        Text(
                          selected.subtitle!,
                          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class _OaSearchSheet extends StatefulWidget {
  final String label;
  final String hint;
  final String emptyText;
  final String initialQuery;
  final List<OaSearchItem> initialItems;
  final Future<List<OaSearchItem>> Function(String query) onSearch;

  const _OaSearchSheet({
    required this.label,
    required this.hint,
    required this.emptyText,
    required this.initialQuery,
    required this.initialItems,
    required this.onSearch,
  });

  @override
  State<_OaSearchSheet> createState() => _OaSearchSheetState();
}

class _OaSearchSheetState extends State<_OaSearchSheet> {
  late final TextEditingController _ctrl;
  Timer? _debounce;
  List<OaSearchItem> _items = [];
  bool _loading = false;
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initialQuery);
    _items = widget.initialItems;
    if (_items.isEmpty) _search(widget.initialQuery);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _search(String query) async {
    final seq = ++_seq;
    setState(() => _loading = true);
    try {
      final items = await widget.onSearch(query);
      if (!mounted || seq != _seq) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || seq != _seq) return;
      setState(() {
        _items = [];
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.78,
        child: Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(widget.label, style: Theme.of(context).textTheme.titleMedium),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _ctrl,
                autofocus: true,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: widget.hint,
                  prefixIcon: const Icon(Icons.search),
                  border: const OutlineInputBorder(),
                ),
                onChanged: (v) {
                  _debounce?.cancel();
                  _debounce = Timer(const Duration(milliseconds: 220), () => _search(v));
                },
                onSubmitted: _search,
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _OaSearchResults(
                items: _items,
                loading: _loading,
                emptyText: widget.emptyText,
                onPick: (item) => Navigator.pop(context, item),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OaSearchResults extends StatelessWidget {
  final List<OaSearchItem> items;
  final bool loading;
  final String emptyText;
  final ValueChanged<OaSearchItem> onPick;

  const _OaSearchResults({
    required this.items,
    required this.loading,
    required this.emptyText,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    if (loading && items.isEmpty) {
      return const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()));
    }
    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(emptyText.isEmpty ? '—' : emptyText, textAlign: TextAlign.center),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: items.length + (loading ? 1 : 0),
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        if (loading && index == items.length) {
          return const Padding(
            padding: EdgeInsets.all(12),
            child: Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))),
          );
        }
        final item = items[index];
        return ListTile(
          leading: Icon(item.icon ?? Icons.badge_outlined),
          title: Text(item.title),
          subtitle: (item.subtitle ?? '').isEmpty ? null : Text(item.subtitle!),
          onTap: () => onPick(item),
        );
      },
    );
  }
}

class OaUserSearchableField extends StatelessWidget {
  final String label;
  final List<Map<String, dynamic>> users;
  final int? valueId;
  final ValueChanged<int?> onChanged;
  final bool enabled;
  final int? Function(Map<String, dynamic>) idOf;
  final String Function(Map<String, dynamic>) labelOf;
  final String emptyText;
  final String hint;

  const OaUserSearchableField({
    super.key,
    required this.label,
    required this.users,
    required this.valueId,
    required this.onChanged,
    required this.idOf,
    required this.labelOf,
    this.enabled = true,
    this.emptyText = '',
    this.hint = '',
  });

  @override
  Widget build(BuildContext context) {
    Map<String, dynamic>? selected;
    for (final u in users) {
      if (idOf(u) == valueId) {
        selected = u;
        break;
      }
    }
    return OaSearchableField(
      label: label,
      hint: hint,
      emptyText: emptyText,
      enabled: enabled,
      prefixIcon: Icons.person_search_outlined,
      value: selected == null || idOf(selected) == null
          ? null
          : OaSearchItem(id: '${idOf(selected)}', title: labelOf(selected), payload: selected),
      onChanged: (item) => onChanged(item == null ? null : int.tryParse(item.id)),
      onSearch: (q) async {
        final needle = q.trim().toLowerCase();
        final filtered = needle.isEmpty
            ? users
            : users.where((u) => labelOf(u).toLowerCase().contains(needle)).toList();
        return [
          for (final u in filtered.take(40))
            if (idOf(u) != null)
              OaSearchItem(id: '${idOf(u)}', title: labelOf(u), icon: Icons.person_outline, payload: u),
        ];
      },
    );
  }
}
