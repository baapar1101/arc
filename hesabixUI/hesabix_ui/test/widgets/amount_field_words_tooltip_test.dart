import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hesabix_ui/widgets/money/amount_field_words_tooltip.dart';

void main() {
  testWidgets('shows amount-in-words overlay on hover after delay', (tester) async {
    final controller = TextEditingController(text: '1,500,000');

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('fa'),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 180,
              child: AmountFieldWordsTooltip(
                controller: controller,
                currencyUnit: 'ریال',
                child: TextField(controller: controller),
              ),
            ),
          ),
        ),
      ),
    );

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);

    await gesture.moveTo(tester.getCenter(find.byType(TextField)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.textContaining('ریال'), findsOneWidget);
    expect(tester.widget<TooltipVisibility>(find.byType(TooltipVisibility)).visible, isFalse);
  });

  testWidgets('hides nested Material Tooltip while words overlay is visible', (tester) async {
    final controller = TextEditingController(text: '250000');

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('fa'),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 220,
              child: AmountFieldWordsTooltip(
                controller: controller,
                currencyUnit: 'ریال',
                child: TextField(
                  controller: controller,
                  decoration: InputDecoration(
                    suffixIcon: IconButton(
                      tooltip: 'nested-material-tooltip',
                      icon: const Icon(Icons.list_alt_outlined),
                      onPressed: () {},
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);

    await gesture.moveTo(tester.getCenter(find.byType(TextField)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(tester.widget<TooltipVisibility>(find.byType(TooltipVisibility)).visible, isFalse);

    await gesture.moveTo(tester.getCenter(find.byIcon(Icons.list_alt_outlined)));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('nested-material-tooltip'), findsNothing);
  });
}
