import 'package:flutter/material.dart';

/// فهرست بلوک‌های خروجی Spec برای ناوبری سریع در پیش‌نمایش.
class HScriptOutlinePanel extends StatelessWidget {
  const HScriptOutlinePanel({
    super.key,
    required this.spec,
    this.onSelect,
  });

  final Map<String, dynamic>? spec;
  final ValueChanged<int>? onSelect;

  static String _labelFor(Map block) {
    final type = block['type']?.toString() ?? 'block';
    final title = block['title']?.toString() ??
        block['label']?.toString() ??
        block['text']?.toString() ??
        block['heading']?.toString();
    final short = (title == null || title.isEmpty)
        ? type
        : (title.length > 36 ? '${title.substring(0, 36)}…' : title);
    switch (type) {
      case 'kpi':
        return 'KPI · $short';
      case 'chart':
        return 'نمودار · $short';
      case 'table':
        return 'جدول · $short';
      case 'title':
        return 'عنوان · $short';
      case 'card':
        return 'کارت · $short';
      case 'section':
        return 'بخش · $short';
      case 'row_break':
        return 'شکست ردیف';
      case 'page_break':
        return 'صفحه جدید';
      default:
        return '$type · $short';
    }
  }

  static IconData _iconFor(String type) {
    switch (type) {
      case 'kpi':
        return Icons.speed;
      case 'chart':
        return Icons.bar_chart;
      case 'table':
        return Icons.table_chart_outlined;
      case 'title':
      case 'heading':
        return Icons.title;
      case 'card':
        return Icons.widgets_outlined;
      case 'gauge':
        return Icons.donut_large;
      default:
        return Icons.view_agenda_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final blocks = (spec?['blocks'] is List) ? List.from(spec!['blocks'] as List) : const [];
    if (blocks.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          'پس از اجرا، ساختار گزارش اینجا دیده می‌شود.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: blocks.length,
      itemBuilder: (context, index) {
        final raw = blocks[index];
        if (raw is! Map) return const SizedBox.shrink();
        final type = raw['type']?.toString() ?? 'block';
        return ListTile(
          dense: true,
          leading: Icon(_iconFor(type), size: 18, color: cs.primary),
          title: Text(_labelFor(raw), maxLines: 1, overflow: TextOverflow.ellipsis),
          onTap: onSelect == null ? null : () => onSelect!(index),
        );
      },
    );
  }
}
