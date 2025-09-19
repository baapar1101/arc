import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hesabix_ui/widgets/data_table/helpers/column_settings_service.dart';
import 'package:hesabix_ui/widgets/data_table/data_table_config.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  
  group('Column Settings Isolation Tests', () {
    test('should have different settings for different tables', () async {
      // Clear any existing settings
      await ColumnSettingsService.clearColumnSettings('table1');
      await ColumnSettingsService.clearColumnSettings('table2');
      
      // Create different settings for two tables
      final settings1 = ColumnSettings(
        visibleColumns: ['id', 'name'],
        columnOrder: ['name', 'id'],
        columnWidths: {'name': 200.0},
      );
      
      final settings2 = ColumnSettings(
        visibleColumns: ['id', 'email', 'createdAt'],
        columnOrder: ['id', 'createdAt', 'email'],
        columnWidths: {'email': 300.0, 'createdAt': 150.0},
      );
      
      // Save settings for both tables
      await ColumnSettingsService.saveColumnSettings('table1', settings1);
      await ColumnSettingsService.saveColumnSettings('table2', settings2);
      
      // Retrieve settings
      final retrieved1 = await ColumnSettingsService.getColumnSettings('table1');
      final retrieved2 = await ColumnSettingsService.getColumnSettings('table2');
      
      // Verify they are different
      expect(retrieved1, isNotNull);
      expect(retrieved2, isNotNull);
      expect(retrieved1!.visibleColumns, equals(['id', 'name']));
      expect(retrieved2!.visibleColumns, equals(['id', 'email', 'createdAt']));
      expect(retrieved1.columnOrder, equals(['name', 'id']));
      expect(retrieved2.columnOrder, equals(['id', 'createdAt', 'email']));
      expect(retrieved1.columnWidths, equals({'name': 200.0}));
      expect(retrieved2.columnWidths, equals({'email': 300.0, 'createdAt': 150.0}));
    });

    test('should generate unique table IDs from endpoints', () {
      // Test different endpoints generate different IDs
      final config1 = DataTableConfig<String>(
        endpoint: '/api/users',
        columns: [],
      );
      
      final config2 = DataTableConfig<String>(
        endpoint: '/api/orders',
        columns: [],
      );
      
      final config3 = DataTableConfig<String>(
        endpoint: '/api/products',
        columns: [],
      );
      
      expect(config1.effectiveTableId, equals('_api_users'));
      expect(config2.effectiveTableId, equals('_api_orders'));
      expect(config3.effectiveTableId, equals('_api_products'));
      
      // All should be different
      expect(config1.effectiveTableId, isNot(equals(config2.effectiveTableId)));
      expect(config2.effectiveTableId, isNot(equals(config3.effectiveTableId)));
      expect(config1.effectiveTableId, isNot(equals(config3.effectiveTableId)));
    });

    test('should use custom tableId when provided', () {
      final config1 = DataTableConfig<String>(
        endpoint: '/api/users',
        tableId: 'custom_users_table',
        columns: [],
      );
      
      final config2 = DataTableConfig<String>(
        endpoint: '/api/users', // Same endpoint
        tableId: 'custom_orders_table', // Different tableId
        columns: [],
      );
      
      expect(config1.effectiveTableId, equals('custom_users_table'));
      expect(config2.effectiveTableId, equals('custom_orders_table'));
      expect(config1.effectiveTableId, isNot(equals(config2.effectiveTableId)));
    });

    test('should handle special characters in endpoints', () {
      final config1 = DataTableConfig<String>(
        endpoint: '/api/v1/users?active=true',
        columns: [],
      );
      
      final config2 = DataTableConfig<String>(
        endpoint: '/api/v2/users?active=false',
        columns: [],
      );
      
      // Special characters should be replaced with underscores
      expect(config1.effectiveTableId, equals('_api_v1_users_active_true'));
      expect(config2.effectiveTableId, equals('_api_v2_users_active_false'));
      expect(config1.effectiveTableId, isNot(equals(config2.effectiveTableId)));
    });

    test('should not interfere with other app data', () async {
      // Save some app data
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_preferences', 'some_value');
      await prefs.setString('theme_settings', 'dark_mode');
      
      // Save column settings
      final settings = ColumnSettings(
        visibleColumns: ['id', 'name'],
        columnOrder: ['name', 'id'],
      );
      await ColumnSettingsService.saveColumnSettings('test_table', settings);
      
      // Verify app data is still intact
      expect(prefs.getString('user_preferences'), equals('some_value'));
      expect(prefs.getString('theme_settings'), equals('dark_mode'));
      
      // Verify column settings are saved
      final retrieved = await ColumnSettingsService.getColumnSettings('test_table');
      expect(retrieved, isNotNull);
      expect(retrieved!.visibleColumns, equals(['id', 'name']));
    });
  });
}
