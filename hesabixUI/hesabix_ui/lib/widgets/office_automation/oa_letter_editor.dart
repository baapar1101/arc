import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

import 'oa_letter_paper.dart';

/// ویرایشگر Markdown/HTML نامه با نوار ابزار و پیش‌نمایش.
class OaLetterEditor extends StatefulWidget {
  final TextEditingController controller;
  final String bodyFormat;
  final ValueChanged<String> onFormatChanged;
  final bool enabled;
  final double minHeight;

  const OaLetterEditor({
    super.key,
    required this.controller,
    required this.bodyFormat,
    required this.onFormatChanged,
    this.enabled = true,
    this.minHeight = 280,
  });

  @override
  State<OaLetterEditor> createState() => _OaLetterEditorState();
}

class _OaLetterEditorState extends State<OaLetterEditor> {
  bool _preview = false;

  void _wrap(String open, String close) {
    if (!widget.enabled) return;
    final sel = widget.controller.selection;
    final text = widget.controller.text;
    final start = !sel.isValid || sel.start < 0 ? text.length : sel.start;
    final end = !sel.isValid || sel.end < 0 ? text.length : sel.end;
    final selected = text.substring(start, end);
    final replaced = '$open$selected$close';
    widget.controller.value = TextEditingValue(
      text: text.replaceRange(start, end, replaced),
      selection: TextSelection.collapsed(offset: start + replaced.length),
    );
  }

  void _linePrefix(String prefix) {
    if (!widget.enabled) return;
    final sel = widget.controller.selection;
    final text = widget.controller.text;
    final start = !sel.isValid || sel.start < 0 ? text.length : sel.start;
    final lineStart = text.lastIndexOf('\n', start - 1) + 1;
    widget.controller.value = TextEditingValue(
      text: text.replaceRange(lineStart, lineStart, prefix),
      selection: TextSelection.collapsed(offset: start + prefix.length),
    );
  }

  Future<void> _insertLink() async {
    final t = AppLocalizations.of(context);
    final url = TextEditingController();
    final label = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.oaInsertLink),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: label, decoration: InputDecoration(labelText: t.oaLinkLabel)),
            const SizedBox(height: 8),
            TextField(controller: url, decoration: InputDecoration(labelText: t.oaLinkUrl)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t.cancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t.oaInsert)),
        ],
      ),
    );
    if (ok != true) {
      url.dispose();
      label.dispose();
      return;
    }
    final href = url.text.trim();
    final text = label.text.trim().isEmpty ? href : label.text.trim();
    url.dispose();
    label.dispose();
    if (href.isEmpty) return;
    if (widget.bodyFormat == 'html') {
      _wrap('<a href="$href">', '</a>');
    } else {
      _wrap('[$text](', '$href)');
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final isHtml = widget.bodyFormat == 'html';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SegmentedButton<String>(
              segments: [
                ButtonSegment(value: 'markdown', label: Text(t.oaMarkdown), icon: const Icon(Icons.notes, size: 16)),
                ButtonSegment(value: 'html', label: Text(t.oaHtml), icon: const Icon(Icons.code, size: 16)),
              ],
              selected: {widget.bodyFormat == 'html' ? 'html' : 'markdown'},
              onSelectionChanged: widget.enabled
                  ? (s) => widget.onFormatChanged(s.first)
                  : null,
            ),
            SegmentedButton<bool>(
              segments: [
                ButtonSegment(value: false, label: Text(t.oaEdit), icon: const Icon(Icons.edit_outlined, size: 16)),
                ButtonSegment(value: true, label: Text(t.oaPreview), icon: const Icon(Icons.visibility_outlined, size: 16)),
              ],
              selected: {_preview},
              onSelectionChanged: (s) => setState(() => _preview = s.first),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (!_preview && widget.enabled)
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              _tool(Icons.format_bold, t.oaBold, () => isHtml ? _wrap('<strong>', '</strong>') : _wrap('**', '**')),
              _tool(Icons.format_italic, t.oaItalic, () => isHtml ? _wrap('<em>', '</em>') : _wrap('*', '*')),
              _tool(Icons.format_underlined, t.oaUnderline, () => isHtml ? _wrap('<u>', '</u>') : _wrap('<u>', '</u>')),
              _tool(Icons.title, t.oaHeading, () => isHtml ? _wrap('<h2>', '</h2>') : _linePrefix('## ')),
              _tool(Icons.format_list_bulleted, t.oaBullet, () => isHtml ? _wrap('<li>', '</li>') : _linePrefix('- ')),
              _tool(Icons.format_quote, t.oaQuote, () => isHtml ? _wrap('<blockquote>', '</blockquote>') : _linePrefix('> ')),
              _tool(Icons.link, t.oaInsertLink, _insertLink),
            ],
          ),
        const SizedBox(height: 8),
        ConstrainedBox(
          constraints: BoxConstraints(minHeight: widget.minHeight),
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: theme.colorScheme.outlineVariant),
              borderRadius: BorderRadius.circular(12),
              color: theme.colorScheme.surface,
            ),
            child: _preview
                ? Padding(
                    padding: const EdgeInsets.all(16),
                    child: widget.bodyFormat == 'html'
                        ? OaHtmlPreview(html: widget.controller.text)
                        : MarkdownBody(
                            data: widget.controller.text.isEmpty ? '*${t.oaBody}*' : widget.controller.text,
                            selectable: true,
                          ),
                  )
                : TextField(
                    controller: widget.controller,
                    enabled: widget.enabled,
                    maxLines: null,
                    minLines: 12,
                    decoration: InputDecoration(
                      hintText: t.oaBodyHint,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.all(16),
                    ),
                    style: theme.textTheme.bodyLarge?.copyWith(height: 1.7),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _tool(IconData icon, String tooltip, VoidCallback onPressed) {
    return IconButton.filledTonal(
      visualDensity: VisualDensity.compact,
      tooltip: tooltip,
      onPressed: widget.enabled ? onPressed : null,
      icon: Icon(icon, size: 18),
    );
  }
}
