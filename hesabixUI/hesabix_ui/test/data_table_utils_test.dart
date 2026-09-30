import 'package:data_table_2/data_table_2.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hesabix_ui/widgets/data_table/helpers/data_table_utils.dart';

void main() {
  test('fixed column table width leaves room for DataTable2 strict check', () {
    final columns = <DataColumn2>[
      const DataColumn2(label: SizedBox.shrink(), fixedWidth: 50),
      const DataColumn2(label: SizedBox.shrink(), fixedWidth: 60),
      const DataColumn2(label: SizedBox.shrink(), fixedWidth: 96),
      const DataColumn2(label: SizedBox.shrink()),
    ];

    final minWidth = DataTableUtils.getFixedColumnsMinTableWidth(
      columns,
      horizontalMargin: 10,
    );

    expect(minWidth, 227);
    expect(minWidth - 20, greaterThan(206));
  });

  testWidgets('fixed width columns lay out inside a narrow parent', (
    tester,
  ) async {
    final columns = <DataColumn2>[
      const DataColumn2(label: Text('A'), fixedWidth: 100),
      const DataColumn2(label: Text('B'), fixedWidth: 150),
      const DataColumn2(label: Text('C'), fixedWidth: 200),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 200,
            height: 200,
            child: DataTable2(
              horizontalMargin: 10,
              minWidth: DataTableUtils.getFixedColumnsMinTableWidth(
                columns,
                horizontalMargin: 10,
              ),
              columns: columns,
              rows: const [],
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
  });
}
