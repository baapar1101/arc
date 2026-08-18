import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'ai_chat_composer_keys.dart';
import 'ai_chat_design.dart';

/// Enter ارسال می‌کند و Shift+Enter خط جدید می‌گذارد.
///
/// هندلر روی [focusNode] مشترک خانه/ترد فقط وقتی پاک می‌شود که هنوز مال
/// همین ویجت باشد؛ وگرنه dispose کامپوزر قبلی میانبر کامپوزر بعدی را می‌کشد.
class AIChatEnterToSend extends StatefulWidget {
  final FocusNode focusNode;
  final VoidCallback onSend;
  final Widget child;
  final bool enabled;
  final VoidCallback? onEnterOverride;

  const AIChatEnterToSend({
    super.key,
    required this.focusNode,
    required this.onSend,
    required this.child,
    this.enabled = true,
    this.onEnterOverride,
  });

  @override
  State<AIChatEnterToSend> createState() => _AIChatEnterToSendState();
}

class _AIChatEnterToSendState extends State<AIChatEnterToSend> {
  late final FocusOnKeyEventCallback _onKey;

  @override
  void initState() {
    super.initState();
    _onKey = _handleKey;
    widget.focusNode.onKeyEvent = _onKey;
  }

  @override
  void didUpdateWidget(covariant AIChatEnterToSend oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      detachComposerKeyHandlerIfOwner(oldWidget.focusNode, _onKey);
      widget.focusNode.onKeyEvent = _onKey;
    }
  }

  @override
  void dispose() {
    detachComposerKeyHandlerIfOwner(widget.focusNode, _onKey);
    super.dispose();
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (!mounted) return KeyEventResult.ignored;
    return handleComposerEnterKeyEvent(
      event: event,
      compactLayout: AIChatDesign.isCompactWidth(context),
      onSend: widget.onSend,
      canSend: widget.enabled,
      onEnterOverride: widget.onEnterOverride,
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

KeyEventResult handleComposerEnterKeyEvent({
  required KeyEvent event,
  required bool compactLayout,
  required VoidCallback onSend,
  bool canSend = true,
  VoidCallback? onEnterOverride,
}) {
  if (event is! KeyDownEvent) return KeyEventResult.ignored;
  final isEnter = event.logicalKey == LogicalKeyboardKey.enter ||
      event.logicalKey == LogicalKeyboardKey.numpadEnter;
  if (!isEnter) return KeyEventResult.ignored;
  if (onEnterOverride != null) {
    onEnterOverride();
    return KeyEventResult.handled;
  }
  if (!composerEnterShouldSend(
    shiftPressed: HardwareKeyboard.instance.isShiftPressed,
    compactLayout: compactLayout,
  )) {
    return KeyEventResult.ignored;
  }
  if (canSend) onSend();
  return KeyEventResult.handled;
}

void detachComposerKeyHandlerIfOwner(
  FocusNode node,
  KeyEventResult Function(FocusNode, KeyEvent) handler,
) {
  if (node.onKeyEvent == handler) {
    node.onKeyEvent = null;
  }
}
