import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Number field that commits on blur, tap-outside, and Enter.
///
/// Studio/print dialogs previously only committed on Enter, so Save/Preview
/// often persisted the stale value (e.g. roll columns stayed at 1).
class LabelCommitNumberField extends StatefulWidget {
  const LabelCommitNumberField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.enabled = true,
    this.decimals = 1,
    this.outlined = false,
  });

  final String label;
  final double value;
  final ValueChanged<double> onChanged;
  final bool enabled;
  final int decimals;
  final bool outlined;

  @override
  State<LabelCommitNumberField> createState() => _LabelCommitNumberFieldState();
}

class _LabelCommitNumberFieldState extends State<LabelCommitNumberField> {
  late final TextEditingController _controller;
  late final FocusNode _focus;
  bool _focused = false;
  double? _lastSent;

  String _format(double value) =>
      widget.decimals == 0 ? value.round().toString() : value.toStringAsFixed(widget.decimals);

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _format(widget.value));
    _focus = FocusNode();
    _focus.addListener(_handleFocus);
  }

  void _handleFocus() {
    if (_focus.hasFocus) {
      _focused = true;
      return;
    }
    _focused = false;
    _commit(revertIfInvalid: true);
  }

  @override
  void didUpdateWidget(covariant LabelCommitNumberField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_focused && oldWidget.value != widget.value) {
      final next = _format(widget.value);
      if (_controller.text != next) {
        _controller.text = next;
      }
    }
  }

  @override
  void dispose() {
    _focus.removeListener(_handleFocus);
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _commit({bool revertIfInvalid = false}) {
    final parsed = double.tryParse(_controller.text.replaceAll(',', '.'));
    if (parsed != null && parsed.isFinite) {
      if (parsed != widget.value && parsed != _lastSent) {
        _lastSent = parsed;
        widget.onChanged(parsed);
      }
      return;
    }
    if (revertIfInvalid) {
      _controller.text = _format(widget.value);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextFormField(
        controller: _controller,
        focusNode: _focus,
        enabled: widget.enabled,
        decoration: InputDecoration(
          labelText: widget.label,
          isDense: true,
          border: widget.outlined ? const OutlineInputBorder() : null,
        ),
        keyboardType: TextInputType.numberWithOptions(decimal: widget.decimals > 0),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,\-]+'))],
        onFieldSubmitted: (_) => _commit(revertIfInvalid: true),
        onTapOutside: (_) {
          _focus.unfocus();
        },
      ),
    );
  }
}
