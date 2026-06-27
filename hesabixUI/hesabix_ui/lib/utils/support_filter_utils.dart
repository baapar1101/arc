import 'package:hesabix_ui/widgets/data_table/data_table_config.dart';

/// تبدیل فیلتر ذخیره‌شده به FilterItem برای DataTable
List<FilterItem> savedFilterToFilterItems(Map<String, dynamic> filters) {
  final items = <FilterItem>[];

  filters.forEach((key, value) {
    if (key == 'assigned_operator_id') {
      if (value == null) {
        items.add(const FilterItem(property: 'assigned_operator_id', operator: 'is_null', value: null));
      } else {
        items.add(FilterItem(property: 'assigned_operator_id', operator: '==', value: value));
      }
    } else if (key == 'priority.name' && value is List) {
      items.add(FilterItem(property: 'priority.name', operator: 'in', value: value));
    } else if (key == 'status.name' && value is List) {
      items.add(FilterItem(property: 'status.name', operator: 'in', value: value));
    } else if (key == 'category.name' && value is List) {
      items.add(FilterItem(property: 'category.name', operator: 'in', value: value));
    } else if (value != null) {
      items.add(FilterItem(property: key, operator: '==', value: value));
    }
  });

  return items;
}
