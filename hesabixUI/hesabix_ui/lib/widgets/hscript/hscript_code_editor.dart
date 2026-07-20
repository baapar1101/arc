import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// ادیتور سادهٔ کد HScript — همیشه LTR با gutter شماره خط.
class HScriptCodeEditor extends StatefulWidget {
  const HScriptCodeEditor({
    super.key,
    required this.controller,
    this.label,
    this.minLines = 12,
    this.onChanged,
  });

  final TextEditingController controller;
  final String? label;
  final int minLines;
  final ValueChanged<String>? onChanged;

  @override
  State<HScriptCodeEditor> createState() => _HScriptCodeEditorState();
}

class _HScriptCodeEditorState extends State<HScriptCodeEditor> {
  final _scrollCtrl = ScrollController();
  final _gutterScrollCtrl = ScrollController();
  late final FocusNode _focus;

  @override
  void initState() {
    super.initState();
    _focus = FocusNode();
    widget.controller.addListener(_onTextChanged);
    _scrollCtrl.addListener(_syncGutter);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    _scrollCtrl.removeListener(_syncGutter);
    _scrollCtrl.dispose();
    _gutterScrollCtrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    if (mounted) setState(() {});
  }

  void _syncGutter() {
    if (!_gutterScrollCtrl.hasClients) return;
    if (_gutterScrollCtrl.offset != _scrollCtrl.offset) {
      _gutterScrollCtrl.jumpTo(_scrollCtrl.offset);
    }
  }

  int get _lineCount {
    final text = widget.controller.text;
    if (text.isEmpty) return 1;
    return '\n'.allMatches(text).length + 1;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final editorBg = isDark ? const Color(0xFF0F172A) : const Color(0xFF1E293B);
    final gutterBg = isDark ? const Color(0xFF0B1220) : const Color(0xFF0F172A);
    final codeStyle = const TextStyle(
      fontFamily: 'monospace',
      fontSize: 13.5,
      height: 1.55,
      color: Color(0xFFE2E8F0),
      letterSpacing: 0.2,
    );
    final gutterStyle = codeStyle.copyWith(
      color: const Color(0xFF64748B),
      fontSize: 12.5,
    );

    final lineCount = _lineCount;
    final gutterWidth = (24.0 + (lineCount.toString().length * 8)).clamp(36.0, 64.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.label != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              widget.label!,
              style: theme.textTheme.labelLarge?.copyWith(color: cs.onSurfaceVariant),
            ),
          ),
        Expanded(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: editorBg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.45)),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Directionality(
                textDirection: TextDirection.ltr,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: gutterWidth,
                      child: ColoredBox(
                        color: gutterBg,
                        child: ListView.builder(
                          controller: _gutterScrollCtrl,
                          physics: const NeverScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(8, 12, 8, 12),
                          itemCount: lineCount,
                          itemBuilder: (_, i) => SizedBox(
                            height: codeStyle.fontSize! * codeStyle.height!,
                            child: Text(
                              '${i + 1}',
                              textAlign: TextAlign.right,
                              style: gutterStyle,
                            ),
                          ),
                        ),
                      ),
                    ),
                    VerticalDivider(
                      width: 1,
                      thickness: 1,
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                    Expanded(
                      child: TextField(
                        controller: widget.controller,
                        focusNode: _focus,
                        scrollController: _scrollCtrl,
                        maxLines: null,
                        expands: true,
                        textAlign: TextAlign.left,
                        textAlignVertical: TextAlignVertical.top,
                        textDirection: TextDirection.ltr,
                        keyboardType: TextInputType.multiline,
                        style: codeStyle,
                        cursorColor: const Color(0xFF38BDF8),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.fromLTRB(12, 12, 12, 12),
                          isCollapsed: false,
                          hintText: '# HScript',
                          hintStyle: TextStyle(
                            fontFamily: 'monospace',
                            color: Color(0xFF64748B),
                          ),
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.deny(RegExp(r'\u0000')),
                        ],
                        onChanged: widget.onChanged,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
