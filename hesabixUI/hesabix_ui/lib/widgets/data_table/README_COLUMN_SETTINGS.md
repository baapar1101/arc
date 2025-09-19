# Column Settings Feature

This feature allows users to customize column visibility and ordering in data tables. The settings are automatically saved and restored for each table.

## Features

- **Column Visibility**: Users can show/hide columns by checking/unchecking them
- **Column Ordering**: Users can reorder columns by dragging them
- **Persistent Storage**: Settings are saved using SharedPreferences and restored on next visit
- **Per-Table Settings**: Each table has its own independent settings
- **Multilingual Support**: Full support for English and Persian languages

## Usage

### Basic Usage

```dart
DataTableWidget<User>(
  config: DataTableConfig<User>(
    endpoint: '/api/users',
    columns: [
      TextColumn('id', 'ID'),
      TextColumn('name', 'Name'),
      TextColumn('email', 'Email'),
      DateColumn('createdAt', 'Created At'),
    ],
    // Enable column settings (enabled by default)
    enableColumnSettings: true,
    // Show column settings button (shown by default)
    showColumnSettingsButton: true,
    // Optional: Provide a unique table ID for settings storage
    tableId: 'users_table',
    // Optional: Callback when settings change
    onColumnSettingsChanged: (settings) {
      print('Column settings changed: ${settings.visibleColumns}');
    },
  ),
  fromJson: (json) => User.fromJson(json),
)
```

### Advanced Configuration

```dart
DataTableWidget<Order>(
  config: DataTableConfig<Order>(
    endpoint: '/api/orders',
    columns: [
      TextColumn('id', 'Order ID'),
      TextColumn('customerName', 'Customer'),
      NumberColumn('amount', 'Amount'),
      DateColumn('orderDate', 'Order Date'),
      ActionColumn('actions', 'Actions', actions: [
        DataTableAction(
          icon: Icons.edit,
          label: 'Edit',
          onTap: (order) => editOrder(order),
        ),
      ]),
    ],
    // Custom table ID for settings storage
    tableId: 'orders_management_table',
    // Disable column settings for this table
    enableColumnSettings: false,
    // Hide column settings button
    showColumnSettingsButton: false,
    // Provide initial column settings
    initialColumnSettings: ColumnSettings(
      visibleColumns: ['id', 'customerName', 'amount'],
      columnOrder: ['id', 'amount', 'customerName'],
    ),
  ),
  fromJson: (json) => Order.fromJson(json),
)
```

## Configuration Options

### DataTableConfig Properties

- `enableColumnSettings` (bool, default: true): Enable/disable column settings functionality
- `showColumnSettingsButton` (bool, default: true): Show/hide the column settings button
- `tableId` (String?): Unique identifier for the table (auto-generated from endpoint if not provided)
- `initialColumnSettings` (ColumnSettings?): Initial column settings to use
- `onColumnSettingsChanged` (Function?): Callback when column settings change

### ColumnSettings Properties

- `visibleColumns` (List<String>): List of visible column keys
- `columnOrder` (List<String>): Ordered list of column keys
- `columnWidths` (Map<String, double>): Custom column widths (future feature)

## How It Works

1. **Settings Storage**: Each table's settings are stored in SharedPreferences with a unique key
2. **Settings Loading**: On table initialization, settings are loaded and applied
3. **Settings Dialog**: Users can modify settings through a drag-and-drop interface
4. **Settings Persistence**: Changes are automatically saved to SharedPreferences
5. **Settings Restoration**: Settings are restored when the table is loaded again

## Storage Key Format

Settings are stored with the key: `data_table_column_settings_{tableId}`

Where `tableId` is either:
- The provided `tableId` from config
- Auto-generated from the endpoint (e.g., `/api/users` becomes `_api_users`)

## Localization

The feature supports both English and Persian languages. Required localization keys:

- `columnSettings`: "Column Settings" / "تنظیمات ستون‌ها"
- `columnSettingsDescription`: "Manage column visibility and order for this table" / "مدیریت نمایش و ترتیب ستون‌های این جدول"
- `columnName`: "Column Name" / "نام ستون"
- `visibility`: "Visibility" / "نمایش"
- `order`: "Order" / "ترتیب"
- `visible`: "Visible" / "نمایش"
- `hidden`: "Hidden" / "مخفی"
- `resetToDefaults`: "Reset to Defaults" / "بازگردانی به پیش‌فرض"
- `save`: "Save" / "ذخیره"
- `error`: "Error" / "خطا"

## Technical Details

### Files Added/Modified

1. **New Files**:
   - `helpers/column_settings_service.dart`: Service for managing settings persistence
   - `column_settings_dialog.dart`: Dialog widget for managing column settings

2. **Modified Files**:
   - `data_table_config.dart`: Added column settings configuration options
   - `data_table_widget.dart`: Integrated column settings functionality
   - `app_en.arb` & `app_fa.arb`: Added localization keys

### Dependencies

- `shared_preferences`: For persistent storage
- `flutter/material.dart`: For UI components
- `data_table_2`: For the data table widget

## Future Enhancements

- Column width customization
- Column grouping
- Export settings with data
- Import/export column configurations
- Column templates/presets
