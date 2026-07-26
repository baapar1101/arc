import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:hesabix_ui/utils/snackbar_helper.dart';
import 'package:markdown/markdown.dart' as md;

/// رندر بلوک‌های fenced code با دکمه کپی در هدر.
class AICopyableCodeBlockBuilder extends MarkdownElementBuilder {
  AICopyableCodeBlockBuilder({
    required this.theme,
    required this.scheme,
  });

  final ThemeData theme;
  final ColorScheme scheme;

  @override
  bool isBlockElement() => true;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    return _CopyableCodeBlock(
      code: element.textContent,
      language: _extractLanguage(element),
      theme: theme,
      scheme: scheme,
      textStyle: preferredStyle ??
          theme.textTheme.bodySmall?.copyWith(
            fontFamily: 'monospace',
            color: scheme.onSurface,
          ),
    );
  }

  static String? _extractLanguage(md.Element element) {
    for (final node in element.children ?? const <md.Node>[]) {
      if (node is! md.Element || node.tag != 'code') continue;
      final cls = node.attributes['class'];
      if (cls == null || cls.isEmpty) continue;
      for (final part in cls.split(RegExp(r'\s+'))) {
        if (part.startsWith('language-') && part.length > 9) {
          return part.substring(9);
        }
      }
    }
    return null;
  }
}

class _CopyableCodeBlock extends StatefulWidget {
  const _CopyableCodeBlock({
    required this.code,
    required this.theme,
    required this.scheme,
    this.language,
    this.textStyle,
  });

  final String code;
  final String? language;
  final ThemeData theme;
  final ColorScheme scheme;
  final TextStyle? textStyle;

  @override
  State<_CopyableCodeBlock> createState() => _CopyableCodeBlockState();
}

class _CopyableCodeBlockState extends State<_CopyableCodeBlock> {
  bool _copied = false;

  Future<void> _copy() async {
    final text = widget.code;
    if (text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    setState(() => _copied = true);
    SnackBarHelper.show(context, message: 'کپی شد');
    await Future<void>.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _copied = false);
  }

  @override
  Widget build(BuildContext context) {
    final lang = widget.language?.trim();
    final showLang = lang != null && lang.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(10, 4, 4, 0),
          child: Row(
            children: [
              if (showLang)
                Expanded(
                  child: Text(
                    lang,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: widget.theme.textTheme.labelSmall?.copyWith(
                      color: widget.scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                )
              else
                const Spacer(),
              IconButton(
                tooltip: _copied ? 'کپی شد' : 'کپی کد',
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                padding: EdgeInsets.zero,
                iconSize: 16,
                onPressed: _copy,
                icon: Icon(
                  _copied ? Icons.check_rounded : Icons.copy_outlined,
                  color: _copied
                      ? widget.scheme.primary
                      : widget.scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: SelectableText(
            widget.code,
            style: widget.textStyle,
          ),
        ),
      ],
    );
  }
}
