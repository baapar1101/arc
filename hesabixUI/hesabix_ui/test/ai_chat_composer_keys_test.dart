import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hesabix_ui/widgets/ai/ai_chat_composer_keys.dart';
import 'package:hesabix_ui/widgets/ai/ai_chat_enter_to_send.dart';

void main() {
  test('desktop Enter sends, Shift+Enter stays newline', () {
    expect(
      composerEnterShouldSend(shiftPressed: false, compactLayout: false),
      isTrue,
    );
    expect(
      composerEnterShouldSend(shiftPressed: true, compactLayout: false),
      isFalse,
    );
  });

  test('compact layout never treats Enter as send', () {
    expect(
      composerEnterShouldSend(shiftPressed: false, compactLayout: true),
      isFalse,
    );
    expect(
      composerEnterShouldSend(shiftPressed: true, compactLayout: true),
      isFalse,
    );
  });

  test('detaching the outgoing handler does not clear the incoming one', () {
    final node = FocusNode();
    addTearDown(node.dispose);

    KeyEventResult first(FocusNode n, KeyEvent e) => KeyEventResult.ignored;
    KeyEventResult second(FocusNode n, KeyEvent e) => KeyEventResult.handled;

    node.onKeyEvent = first;
    node.onKeyEvent = second;
    detachComposerKeyHandlerIfOwner(node, first);
    expect(node.onKeyEvent, equals(second));

    detachComposerKeyHandlerIfOwner(node, second);
    expect(node.onKeyEvent, isNull);
  });

  testWidgets(
    'Enter still sends after overlapping composers share a FocusNode',
    (tester) async {
      tester.view.physicalSize = const Size(900, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final focus = FocusNode();
      final controller = TextEditingController(text: 'پیام');
      addTearDown(focus.dispose);
      addTearDown(controller.dispose);

      var sendCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: _OverlapHarness(
            focus: focus,
            controller: controller,
            showOutgoing: true,
            showIncoming: false,
            onSend: () => sendCount++,
          ),
        ),
      );

      await tester.tap(find.byType(TextField));
      await tester.pump();

      final harness = tester.state<_OverlapHarnessState>(
        find.byType(_OverlapHarness),
      );
      harness.showBoth();
      await tester.pump();
      harness.showOnlyIncoming();
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(sendCount, 1);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      expect(sendCount, 1);
    },
  );
}

class _OverlapHarness extends StatefulWidget {
  final FocusNode focus;
  final TextEditingController controller;
  final bool showOutgoing;
  final bool showIncoming;
  final VoidCallback onSend;

  const _OverlapHarness({
    required this.focus,
    required this.controller,
    required this.showOutgoing,
    required this.showIncoming,
    required this.onSend,
  });

  @override
  State<_OverlapHarness> createState() => _OverlapHarnessState();
}

class _OverlapHarnessState extends State<_OverlapHarness> {
  late bool _showOutgoing = widget.showOutgoing;
  late bool _showIncoming = widget.showIncoming;

  void showBoth() {
    setState(() {
      _showOutgoing = true;
      _showIncoming = true;
    });
  }

  void showOnlyIncoming() {
    setState(() {
      _showOutgoing = false;
      _showIncoming = true;
    });
  }

  Widget _binder(Key key) {
    return AIChatEnterToSend(
      key: key,
      focusNode: widget.focus,
      enabled: true,
      onSend: widget.onSend,
      child: const SizedBox.shrink(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          if (_showOutgoing) _binder(const ValueKey('outgoing')),
          if (_showIncoming) _binder(const ValueKey('incoming')),
          TextField(
            controller: widget.controller,
            focusNode: widget.focus,
            maxLines: 4,
            textInputAction: TextInputAction.newline,
          ),
        ],
      ),
    );
  }
}
