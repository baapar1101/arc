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
      
      final merged = ColumnSettingsService.mergeWithDefaults(userSettings, defaultKeys);
      
      // Should have at least one column visible
      expect(merged.visibleColumns, isNotEmpty);
      expect(merged.visibleColumns.length, greaterThanOrEqualTo(1));
      expect(merged.visibleColumns.first, equals('id')); // First column should be visible
    });

    test('should preserve existing visible columns', () {
      final defaultKeys = ['id', 'name', 'email', 'createdAt'];
      final userSettings = ColumnSettings(
        visibleColumns: ['name', 'email'], // Some columns visible
        columnOrder: ['name', 'email'],
        columnWidths: {'name': 200.0},
      );
      
      final merged = ColumnSettingsService.mergeWithDefaults(userSettings, defaultKeys);
      
      expect(merged.visibleColumns, equals(['name', 'email']));
      expect(merged.columnOrder, equals(['name', 'email']));
      expect(merged.columnWidths, equals({'name': 200.0}));
    });

    test('should handle empty default keys gracefully', () {
      final defaultKeys = <String>[];
      final userSettings = ColumnSettings(
        visibleColumns: [],
        columnOrder: [],
        columnWidths: {},
      );
      
      final merged = ColumnSettingsService.mergeWithDefaults(userSettings, defaultKeys);
      
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
      
      final merged = ColumnSettingsService.mergeWithDefaults(userSettings, defaultKeys);
      
      // Should have at least one valid column visible
      expect(merged.visibleColumns, isNotEmpty);
      expect(merged.visibleColumns.length, greaterThanOrEqualTo(1));
      expect(merged.visibleColumns.first, equals('id')); // First valid column
      
      // Should filter out invalid column widths (name is not in visible columns)
      expect(merged.columnWidths, isEmpty);
    });

    test('should maintain column order when adding missing columns', () {
      final defaultKeys = ['id', 'name', 'email', 'createdAt'];
      final userSettings = ColumnSettings(
        visibleColumns: ['name', 'email'],
        columnOrder: ['name', 'email', 'id'], // 'id' is not in visible but in order
        columnWidths: {},
      );
      
      final merged = ColumnSettingsService.mergeWithDefaults(userSettings, defaultKeys);
      
      expect(merged.visibleColumns, equals(['name', 'email']));
      expect(merged.columnOrder, equals(['name', 'email'])); // Should filter out 'id'
    });
  });
}
