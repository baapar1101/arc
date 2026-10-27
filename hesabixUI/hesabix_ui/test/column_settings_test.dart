import 'package:flutter_test/flutter_test.dart';
import 'package:hesabix_ui/widgets/data_table/helpers/column_settings_service.dart';

void main() {
  group('ColumnSettingsService', () {
    test('should create default settings from column keys', () {
      final columnKeys = ['id', 'name', 'email', 'createdAt'];
      final settings = ColumnSettingsService.getDefaultSettings(columnKeys);

      expect(settings.visibleColumns, equals(columnKeys));
      expect(settings.columnOrder, equals(columnKeys));
      expect(settings.columnWidths, isEmpty);
    });

    test('should expose newly available default columns', () {
      final defaultKeys = ['id', 'name', 'email', 'createdAt', 'updatedAt'];
      final userSettings = ColumnSettings(
        visibleColumns: ['id', 'name', 'email'],
        columnOrder: ['name', 'id', 'email'],
        columnWidths: {'name': 200.0},
      );

      final merged = ColumnSettingsService.mergeWithDefaults(
        userSettings,
        defaultKeys,
      );

      expect(
        merged.visibleColumns,
        equals(['id', 'name', 'email', 'createdAt', 'updatedAt']),
      );
      expect(
        merged.columnOrder,
        equals(['name', 'id', 'email', 'createdAt', 'updatedAt']),
      );
      expect(merged.columnWidths, equals({'name': 200.0}));
    });

    test('should not treat a hidden known column as a newly introduced column', () {
      final defaultKeys = ['id', 'name', 'email'];
      final userSettings = ColumnSettings(
        visibleColumns: ['id', 'name'],
        columnOrder: ['name', 'id', 'email'],
      );

      final merged = ColumnSettingsService.mergeWithDefaults(
        userSettings,
        defaultKeys,
      );

      expect(merged.visibleColumns, equals(['id', 'name']));
      expect(merged.columnOrder, equals(['name', 'id', 'email']));
    });

    test('should handle null user settings', () {
      final defaultKeys = ['id', 'name', 'email'];
      final merged = ColumnSettingsService.mergeWithDefaults(null, defaultKeys);

      expect(merged.visibleColumns, equals(defaultKeys));
      expect(merged.columnOrder, equals(defaultKeys));
      expect(merged.columnWidths, isEmpty);
    });

    test('should filter out invalid columns from user settings', () {
      final defaultKeys = ['id', 'name', 'email'];
      final userSettings = ColumnSettings(
        visibleColumns: ['id', 'name', 'invalidColumn', 'email'],
        columnOrder: ['name', 'invalidColumn', 'id', 'email'],
        columnWidths: {'name': 200.0, 'invalidColumn': 150.0},
      );

      final merged = ColumnSettingsService.mergeWithDefaults(
        userSettings,
        defaultKeys,
      );

      expect(merged.visibleColumns, equals(['id', 'name', 'email']));
      expect(merged.columnOrder, equals(['name', 'id', 'email']));
      expect(merged.columnWidths, equals({'name': 200.0}));
    });
  });

  group('ColumnSettings', () {
    test('should serialize and deserialize correctly', () {
      final original = ColumnSettings(
        visibleColumns: ['id', 'name', 'email'],
        columnOrder: ['name', 'id', 'email'],
        columnWidths: {'name': 200.0, 'email': 150.0},
      );

      final json = original.toJson();
      final restored = ColumnSettings.fromJson(json);

      expect(restored.visibleColumns, equals(original.visibleColumns));
      expect(restored.columnOrder, equals(original.columnOrder));
      expect(restored.columnWidths, equals(original.columnWidths));
    });

    test('should copy with new values correctly', () {
      final original = ColumnSettings(
        visibleColumns: ['id', 'name'],
        columnOrder: ['name', 'id'],
        columnWidths: {'name': 200.0},
      );

      final copied = original.copyWith(
        visibleColumns: ['id', 'name', 'email'],
        columnWidths: {'name': 250.0, 'email': 150.0},
      );

      expect(copied.visibleColumns, equals(['id', 'name', 'email']));
      expect(copied.columnOrder, equals(['name', 'id'])); // unchanged
      expect(copied.columnWidths, equals({'name': 250.0, 'email': 150.0}));
    });

    test('should round-trip sort preference', () {
      final original = ColumnSettings(
        visibleColumns: ['id', 'name'],
        columnOrder: ['name', 'id'],
        sortBy: 'name',
        sortDesc: true,
        sorts: const [
          ColumnSortSpec(by: 'name', desc: true),
          ColumnSortSpec(by: 'id', desc: false),
        ],
        hasSortPreference: true,
      );

      final restored = ColumnSettings.fromJson(original.toJson());
      expect(restored.hasSortPreference, isTrue);
      expect(restored.sortBy, 'name');
      expect(restored.sortDesc, isTrue);
      expect(restored.sorts, hasLength(2));
      expect(restored.sorts.first.by, 'name');
      expect(restored.sorts.first.desc, isTrue);
      expect(restored.sorts.last.by, 'id');
    });

    test('legacy json without sort does not override table default sort', () {
      final restored = ColumnSettings.fromJson({
        'visibleColumns': ['id'],
        'columnOrder': ['id'],
      });
      expect(restored.hasSortPreference, isFalse);
      expect(restored.sorts, isEmpty);
    });
  });
}
