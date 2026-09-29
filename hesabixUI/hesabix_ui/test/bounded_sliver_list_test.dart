import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hesabix_ui/widgets/common/bounded_sliver_list.dart';

void main() {
  testWidgets('bounded sliver list lazily builds viewport rows', (tester) async {
    var built = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomScrollView(
            cacheExtent: 320,
            slivers: [
              BoundedSliverList(
                itemCount: 1000,
                itemBuilder: (context, index) {
                  built++;
                  return SizedBox(
                    height: 72,
                    child: Text('Task $index'),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );

    expect(built, greaterThan(0));
    expect(
      built,
      lessThan(100),
      reason: 'A 1,000-row logical list must not eagerly build all rows.',
    );
    expect(find.text('Task 999'), findsNothing);

    await tester.scrollUntilVisible(
      find.text('Task 250'),
      600,
      scrollable: find.byType(Scrollable),
    );
    await tester.pumpAndSettle();

    expect(find.text('Task 250'), findsOneWidget);
    expect(built, lessThan(400));
  });
}
