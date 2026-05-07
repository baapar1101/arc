import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../models/invoice_tag_ref.dart';
import '../../utils/error_extractor.dart';

/// انتخاب چند برچسب برای فاکتور + ایجاد برچسب سفارشی
class InvoiceTagsField extends StatefulWidget {
  final int businessId;
  final ApiClient apiClient;
  final List<int> selectedTagIds;
  final ValueChanged<List<int>> onChanged;
  final String label;
  final bool allowCreate;

  const InvoiceTagsField({
    super.key,
    required this.businessId,
    required this.apiClient,
    required this.selectedTagIds,
    required this.onChanged,
    this.label = 'برچسب‌ها',
    this.allowCreate = true,
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

  Future<void> _createTag() async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('برچسب جدید'),
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

  void _toggle(int id) {
    final set = widget.selectedTagIds.toSet();
    if (set.contains(id)) {
      set.remove(id);
    } else {
      set.add(id);
    }
    widget.onChanged(set.toList()..sort());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_loading) {
      return Row(
        children: [
          Text(widget.label, style: theme.textTheme.titleSmall),
          const SizedBox(width: 8),
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
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final t in _all)
              FilterChip(
                label: Text(t.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                selected: widget.selectedTagIds.contains(t.id),
                onSelected: (_) => _toggle(t.id),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
          ],
        ),
      ],
    );
  }
}
