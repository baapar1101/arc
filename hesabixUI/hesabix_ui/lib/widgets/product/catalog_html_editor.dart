import 'package:flutter/material.dart';

/// ویرایشگر HTML سبک برای «بررسی تخصصی» کاتالوگ.
class CatalogHtmlEditor extends StatefulWidget {
  final String? initialValue;
  final ValueChanged<String?> onChanged;
  final String label;
  final String? helperText;
  final int minLines;

  const CatalogHtmlEditor({
    super.key,
    this.initialValue,
    required this.onChanged,
    this.label = 'بررسی تخصصی',
    this.helperText,
    this.minLines = 8,
  });

  @override
  State<CatalogHtmlEditor> createState() => _CatalogHtmlEditorState();
}

class _CatalogHtmlEditorState extends State<CatalogHtmlEditor> {
  late final TextEditingController _controller;
  bool _preview = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue ?? '');
  }

  @override
  void didUpdateWidget(covariant CatalogHtmlEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = widget.initialValue ?? '';
    if (next != _controller.text) {
      _controller.value = TextEditingValue(
        text: next,
        selection: TextSelection.collapsed(offset: next.length),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _emit() {
    final v = _controller.text.trim();
    widget.onChanged(v.isEmpty ? null : v);
  }

  void _wrap(String open, String close) {
    final sel = _controller.selection;
    final text = _controller.text;
    if (!sel.isValid) return;
    final start = sel.start < 0 ? text.length : sel.start;
    final end = sel.end < 0 ? text.length : sel.end;
    final selected = text.substring(start, end);
    final replaced = '$open$selected$close';
    final newText = text.replaceRange(start, end, replaced);
    _controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: start + replaced.length),
    );
    _emit();
  }

  void _insert(String snippet) {
    final sel = _controller.selection;
    final text = _controller.text;
    final pos = sel.start < 0 ? text.length : sel.start;
    final newText = text.replaceRange(pos, pos, snippet);
    _controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: pos + snippet.length),
    );
    _emit();
  }

  Future<void> _insertLink() async {
    final urlCtrl = TextEditingController();
    final labelCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('درج لینک'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: labelCtrl,
              decoration: const InputDecoration(labelText: 'متن نمایشی'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: urlCtrl,
              decoration: const InputDecoration(labelText: 'آدرس (https://…)'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('درج')),
        ],
      ),
    );
    if (ok != true) return;
    final url = urlCtrl.text.trim();
    if (url.isEmpty) return;
    final label = labelCtrl.text.trim().isEmpty ? url : labelCtrl.text.trim();
    _insert('<a href="$url" target="_blank" rel="noopener">$label</a>');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text(widget.label, style: theme.textTheme.titleSmall)),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('ویرایش'), icon: Icon(Icons.edit_outlined, size: 16)),
                ButtonSegment(value: true, label: Text('پیش‌نمایش'), icon: Icon(Icons.visibility_outlined, size: 16)),
              ],
              selected: {_preview},
              onSelectionChanged: (s) => setState(() => _preview = s.first),
            ),
          ],
        ),
        if (widget.helperText != null) ...[
          const SizedBox(height: 4),
          Text(widget.helperText!, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ],
        const SizedBox(height: 8),
        if (!_preview) ...[
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              _toolBtn(Icons.format_bold, 'Bold', () => _wrap('<strong>', '</strong>')),
              _toolBtn(Icons.format_italic, 'Italic', () => _wrap('<em>', '</em>')),
              _toolBtn(Icons.format_underlined, 'Underline', () => _wrap('<u>', '</u>')),
              _toolBtn(Icons.title, 'Heading', () => _wrap('<h3>', '</h3>')),
              _toolBtn(Icons.format_list_bulleted, 'List', () => _insert('<ul>\n<li></li>\n</ul>')),
              _toolBtn(Icons.format_list_numbered, 'Numbered', () => _insert('<ol>\n<li></li>\n</ol>')),
              _toolBtn(Icons.link, 'Link', _insertLink),
              _toolBtn(Icons.horizontal_rule, 'Line', () => _insert('<br />')),
            ],
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _controller,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
            minLines: widget.minLines,
            maxLines: 16,
            onChanged: (_) => _emit(),
          ),
        ] else
          Container(
            constraints: const BoxConstraints(minHeight: 160),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border.all(color: theme.dividerColor),
              borderRadius: BorderRadius.circular(8),
              color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
            ),
            child: _CatalogHtmlPreview(html: _controller.text),
          ),
      ],
    );
  }

  Widget _toolBtn(IconData icon, String tooltip, VoidCallback onTap) {
    return IconButton(
      tooltip: tooltip,
      icon: Icon(icon, size: 20),
      visualDensity: VisualDensity.compact,
      onPressed: onTap,
    );
  }
}

class _CatalogHtmlPreview extends StatelessWidget {
  final String html;

  const _CatalogHtmlPreview({required this.html});

  @override
  Widget build(BuildContext context) {
    if (html.trim().isEmpty) {
      return Text(
        'پیش‌نمایشی برای نمایش وجود ندارد.',
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      );
    }
    return SelectionArea(child: _CatalogHtmlBlock(nodes: _parseHtml(html)));
  }
}

class _HtmlNode {
  final String tag;
  final String? href;
  final String text;
  final List<_HtmlNode> children;

  _HtmlNode({
    required this.tag,
    this.href,
    this.text = '',
    this.children = const [],
  });
}

List<_HtmlNode> _parseHtml(String raw) {
  final cleaned = raw
      .replaceAll(RegExp(r'<script[\s\S]*?</script>', caseSensitive: false), '')
      .replaceAll(RegExp(r'<style[\s\S]*?</style>', caseSensitive: false), '');
  final re = RegExp(
    r'(<h3[^>]*>[\s\S]*?</h3>|<p[^>]*>[\s\S]*?</p>|<ul[^>]*>[\s\S]*?</ul>|<ol[^>]*>[\s\S]*?</ol>|<li[^>]*>[\s\S]*?</li>|<a[^>]*>[\s\S]*?</a>|<br\s*/?>|[^<]+)',
    caseSensitive: false,
  );
  final nodes = <_HtmlNode>[];
  for (final m in re.allMatches(cleaned)) {
    final chunk = m.group(0) ?? '';
    if (chunk.trim().isEmpty) continue;
    final lower = chunk.toLowerCase();
    if (lower.startsWith('<h3')) {
      nodes.add(_HtmlNode(tag: 'h3', text: _stripTags(chunk)));
    } else if (lower.startsWith('<p')) {
      nodes.add(_HtmlNode(tag: 'p', text: _stripTags(chunk)));
    } else if (lower.startsWith('<ul')) {
      nodes.add(_HtmlNode(tag: 'ul', children: _parseListItems(chunk)));
    } else if (lower.startsWith('<ol')) {
      nodes.add(_HtmlNode(tag: 'ol', children: _parseListItems(chunk)));
    } else if (lower.startsWith('<a')) {
      final href = RegExp(r'href="([^"]+)"', caseSensitive: false).firstMatch(chunk)?.group(1);
      nodes.add(_HtmlNode(tag: 'a', href: href, text: _stripTags(chunk)));
    } else if (RegExp(r'^<br\s*/?>$', caseSensitive: false).hasMatch(chunk.trim())) {
      nodes.add(_HtmlNode(tag: 'br'));
    } else if (!chunk.trim().startsWith('<')) {
      nodes.add(_HtmlNode(tag: 'text', text: chunk.trim()));
    }
  }
  return nodes;
}

List<_HtmlNode> _parseListItems(String block) {
  final items = <_HtmlNode>[];
  final re = RegExp(r'<li[^>]*>([\s\S]*?)</li>', caseSensitive: false);
  for (final m in re.allMatches(block)) {
    items.add(_HtmlNode(tag: 'li', text: _stripTags(m.group(1) ?? '')));
  }
  return items;
}

String _stripTags(String input) {
  return input.replaceAll(RegExp(r'<[^>]+>'), '').replaceAll('&nbsp;', ' ').trim();
}

class _CatalogHtmlBlock extends StatelessWidget {
  final List<_HtmlNode> nodes;

  const _CatalogHtmlBlock({required this.nodes});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final children = <Widget>[];
    for (final n in nodes) {
      switch (n.tag) {
        case 'h3':
          children.add(Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 4),
            child: Text(n.text, style: theme.textTheme.titleMedium),
          ));
          break;
        case 'p':
        case 'text':
          children.add(Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(n.text, style: theme.textTheme.bodyMedium),
          ));
          break;
        case 'a':
          children.add(Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(n.text, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.primary)),
          ));
          break;
        case 'br':
          children.add(const SizedBox(height: 8));
          break;
        case 'ul':
        case 'ol':
          children.add(Padding(
            padding: const EdgeInsets.only(bottom: 8, right: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: n.children.asMap().entries.map((e) {
                final prefix = n.tag == 'ol' ? '${e.key + 1}. ' : '• ';
                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text('$prefix${e.value.text}', style: theme.textTheme.bodyMedium),
                );
              }).toList(),
            ),
          ));
          break;
      }
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: children);
  }
}
