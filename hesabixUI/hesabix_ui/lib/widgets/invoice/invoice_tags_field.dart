import 'package:hesabix_ui/theme/glass.dart';
import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../models/invoice_tag_ref.dart';
import '../../utils/error_extractor.dart';

/// انتخاب چند برچسب برای فاکتور + ایجاد/ویرایش/حذف برچسب سفارشی
class InvoiceTagsField extends StatefulWidget {
  final int businessId;
  final ApiClient apiClient;
  final List<int> selectedTagIds;
  final ValueChanged<List<int>> onChanged;
  final String label;
  final bool allowCreate;
  /// نمایش داخل بخش فرم فاکتور بدون عنوان جداگانه.
  final bool embedded;

  const InvoiceTagsField({
    super.key,
    required this.businessId,
    required this.apiClient,
    required this.selectedTagIds,
    required this.onChanged,
    this.label = 'برچسب‌ها',
    this.allowCreate = true,
    this.embedded = false,
  });

  @override
  State<InvoiceTagsField> createState() => _InvoiceTagsFieldState();
}

class _InvoiceTagsFieldState extends State<InvoiceTagsField> {
  bool _loading = true;
  String? _error;
  List<InvoiceTagRef> _all = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await widget.apiClient.get<Map<String, dynamic>>(
        '/api/v1/invoices/business/${widget.businessId}/tags',
      );
      final data = res.data;
      final items = (data?['data']?['items'] as List<dynamic>?) ?? [];
      if (!mounted) return;
      setState(() {
        _all = items
            .whereType<Map<String, dynamic>>()
            .map(InvoiceTagRef.fromJson)
            .where((t) => t.isActive)
            .toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = ErrorExtractor.userMessage(e);
      });
    }
  }

  Future<String?> _promptTagName({
    required String title,
    String? initial,
  }) async {
    final ctrl = TextEditingController(text: initial ?? '');
    final name = await showGlassDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(
            labelText: 'نام برچسب',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('انصراف')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('ثبت'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    return name;
  }

  Future<void> _patchTag(int tagId, Map<String, dynamic> data) async {
    await widget.apiClient.patch<Map<String, dynamic>>(
      '/api/v1/invoices/business/${widget.businessId}/tags/$tagId',
      data: data,
    );
  }

  Future<void> _createTag() async {
    final name = await _promptTagName(title: 'برچسب جدید');
    if (name == null || name.isEmpty) return;
    try {
      final res = await widget.apiClient.post<Map<String, dynamic>>(
        '/api/v1/invoices/business/${widget.businessId}/tags',
        data: {'name': name},
      );
      final raw = res.data?['data']?['item'];
      int? newId;
      if (raw is Map<String, dynamic> && raw['id'] != null) {
        newId = (raw['id'] as num).toInt();
      }
      await _load();
      if (!mounted) return;
      if (newId != null) {
        final next = {...widget.selectedTagIds, newId}.toList()..sort();
        widget.onChanged(next);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ErrorExtractor.forContext(e, context))),
      );
    }
  }

  Future<void> _editTag(InvoiceTagRef tag) async {
    if (tag.isSystem) return;
    final name = await _promptTagName(title: 'ویرایش برچسب', initial: tag.name);
    if (name == null || name.isEmpty || name == tag.name) return;
    try {
      await _patchTag(tag.id, {'name': name});
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ErrorExtractor.forContext(e, context))),
      );
    }
  }

  Future<void> _deleteTag(InvoiceTagRef tag) async {
    if (tag.isSystem) return;
    final theme = Theme.of(context);
    final ok = await showGlassDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف برچسب'),
        content: Text('برچسب «${tag.name}» حذف شود؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: theme.colorScheme.error),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _patchTag(tag.id, {'is_active': false});
      await _load();
      if (!mounted) return;
      if (widget.selectedTagIds.contains(tag.id)) {
        widget.onChanged(
          widget.selectedTagIds.where((id) => id != tag.id).toList(),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ErrorExtractor.forContext(e, context))),
      );
    }
  }

  void _showTagMenu(InvoiceTagRef tag) {
    if (tag.isSystem) return;
    final theme = Theme.of(context);
    showGlassModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              dense: true,
              visualDensity: VisualDensity.compact,
              leading: const Icon(Icons.edit_outlined, size: 20),
              title: const Text('ویرایش نام'),
              onTap: () {
                Navigator.pop(ctx);
                _editTag(tag);
              },
            ),
            ListTile(
              dense: true,
              visualDensity: VisualDensity.compact,
              leading: Icon(Icons.delete_outline, size: 20, color: theme.colorScheme.error),
              title: Text('حذف', style: TextStyle(color: theme.colorScheme.error)),
              onTap: () {
                Navigator.pop(ctx);
                _deleteTag(tag);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _toggle(int id) {
    final set = widget.selectedTagIds.toSet();
    if (set.contains(id)) {
      set.remove(id);
    } else {
      set.add(id);
    }
    widget.onChanged(set.toList()..sort());
  }

  Widget _buildTagChip(InvoiceTagRef t) {
    final chip = FilterChip(
      label: Text(t.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      selected: widget.selectedTagIds.contains(t.id),
      onSelected: (_) => _toggle(t.id),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
    if (t.isSystem) return chip;
    return Tooltip(
      message: 'نگه دارید برای ویرایش یا حذف',
      child: GestureDetector(
        onLongPress: () => _showTagMenu(t),
        child: chip,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_loading) {
      return Row(
        children: [
          if (!widget.embedded)
            Text(widget.label, style: theme.textTheme.titleSmall),
          if (!widget.embedded) const SizedBox(width: 8),
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ],
      );
    }
    if (_error != null) {
      return Row(
        children: [
          Expanded(child: Text(_error!, style: TextStyle(color: theme.colorScheme.error))),
          TextButton(onPressed: _load, child: const Text('تلاش مجدد')),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!widget.embedded)
          Row(
            children: [
              Text(widget.label, style: theme.textTheme.titleSmall),
              if (widget.allowCreate) ...[
                const Spacer(),
                TextButton.icon(
                  onPressed: _createTag,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('برچسب جدید'),
                ),
              ],
            ],
          )
        else
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.label,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              if (widget.allowCreate)
                TextButton.icon(
                  onPressed: _createTag,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('برچسب جدید'),
                ),
            ],
          ),
        SizedBox(height: widget.embedded ? 6 : 4),
        Container(
          width: double.infinity,
          padding: widget.embedded
              ? const EdgeInsets.symmetric(horizontal: 8, vertical: 6)
              : EdgeInsets.zero,
          decoration: widget.embedded
              ? BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: theme.colorScheme.outlineVariant.withValues(alpha: 0.8),
                  ),
                )
              : null,
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final t in _all) _buildTagChip(t),
            ],
          ),
        ),
      ],
    );
  }
}
