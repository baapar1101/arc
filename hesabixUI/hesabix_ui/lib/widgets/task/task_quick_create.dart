import 'package:flutter/material.dart';
import 'package:hesabix_ui/theme/glass.dart';

/// Plane-inspired quick-create surface: type a title and press Enter.
/// The parent owns persistence so this widget stays presentation-only.
class TaskQuickCreate extends StatefulWidget {
  final bool enabled;
  final Future<bool> Function(String title) onCreate;

  const TaskQuickCreate({
    super.key,
    required this.enabled,
    required this.onCreate,
  });

  @override
  State<TaskQuickCreate> createState() => _TaskQuickCreateState();
}

class _TaskQuickCreateState extends State<TaskQuickCreate> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final title = _controller.text.trim();
    if (!widget.enabled || _saving || title.isEmpty) return;
    setState(() => _saving = true);
    try {
      final created = await widget.onCreate(title);
      if (!mounted) return;
      if (created) {
        _controller.clear();
        _focusNode.requestFocus();
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GlassSurface(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      borderRadius: BorderRadius.circular(16),
      child: Row(
        children: [
          Icon(Icons.add_task_rounded, color: scheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              enabled: widget.enabled && !_saving,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              decoration: const InputDecoration(
                hintText: 'عنوان کار را بنویسید و Enter بزنید…',
                border: InputBorder.none,
                isDense: true,
              ),
            ),
          ),
          const SizedBox(width: 8),
          if (_saving)
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            IconButton(
              tooltip: 'ایجاد کار',
              onPressed: widget.enabled ? _submit : null,
              icon: const Icon(Icons.arrow_forward_rounded),
            ),
        ],
      ),
    );
  }
}
