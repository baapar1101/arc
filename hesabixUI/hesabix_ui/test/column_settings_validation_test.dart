import 'package:flutter_test/flutter_test.dart';
import 'package:hesabix_ui/widgets/data_table/helpers/column_settings_service.dart';

void main() {
  group('Column Settings Validation Tests', () {
    test('should prevent hiding all columns in mergeWithDefaults', () {
      final defaultKeys = ['id', 'name', 'email', 'createdAt'];
      final userSettings = ColumnSettings(
        visibleColumns: [], // Empty - should be prevented
        columnOrder: [],
        columnWidths: {},
      );

      final merged = ColumnSettingsService.mergeWithDefaults(
        userSettings,
        defaultKeys,
      );

      // Should have at least one column visible
      expect(merged.visibleColumns, isNotEmpty);
      expect(merged.visibleColumns.length, greaterThanOrEqualTo(1));
      expect(
        merged.visibleColumns.first,
        equals('id'),
      ); // First column should be visible
    });

    test(
      'should preserve existing columns and expose newly available columns',
      () {
        final defaultKeys = ['id', 'name', 'email', 'createdAt'];
        final userSettings = ColumnSettings(
          visibleColumns: ['name', 'email'], // Some columns visible
          columnOrder: ['name', 'email'],
          columnWidths: {'name': 200.0},
        );

        final merged = ColumnSettingsService.mergeWithDefaults(
          userSettings,
          defaultKeys,
        );

        expect(merged.visibleColumns, equals(defaultKeys));
        expect(
          merged.columnOrder,
          equals(['name', 'email', 'id', 'createdAt']),
        );
        expect(merged.columnWidths, equals({'name': 200.0}));
      },
    );

    test('should handle empty default keys gracefully', () {
      final defaultKeys = <String>[];
      final userSettings = ColumnSettings(
        visibleColumns: [],
        columnOrder: [],
        columnWidths: {},
      );

      final merged = ColumnSettingsService.mergeWithDefaults(
        userSettings,
        defaultKeys,
      );

      // Should return empty settings when no default keys
      expect(merged.visibleColumns, isEmpty);
      expect(merged.columnOrder, isEmpty);
      expect(merged.columnWidths, isEmpty);
    });

    test('should filter out invalid columns and ensure at least one visible', () {
      final defaultKeys = ['id', 'name', 'email'];
      final userSettings = ColumnSettings(
        visibleColumns: ['invalid1', 'invalid2'], // Invalid columns
        columnOrder: ['invalid1', 'invalid2'],
        columnWidths: {'invalid1': 200.0, 'name': 150.0},
      );

      final merged = ColumnSettingsService.mergeWithDefaults(
        userSettings,
        defaultKeys,
      );

      // Invalid saved columns are discarded; newly available defaults are shown.
      expect(merged.visibleColumns, equals(defaultKeys));
      expect(merged.columnOrder, equals(defaultKeys));
      expect(merged.columnWidths, equals({'name': 150.0}));
    });

    test('should keep explicitly hidden columns hidden and preserve their order', () {
      final defaultKeys = ['id', 'name', 'email', 'createdAt'];
      final userSettings = ColumnSettings(
        visibleColumns: ['name', 'email'],
        columnOrder: [
          'name',
          'email',
          'id',
        ],
        columnWidths: {'id': 120.0},
      );

      final merged = ColumnSettingsService.mergeWithDefaults(
        userSettings,
        defaultKeys,
      );

      expect(merged.visibleColumns, equals(['name', 'email', 'createdAt']));
      expect(merged.columnOrder, equals(['name', 'email', 'id', 'createdAt']));
      expect(merged.columnWidths, equals({'id': 120.0}));
    });
  });
}
