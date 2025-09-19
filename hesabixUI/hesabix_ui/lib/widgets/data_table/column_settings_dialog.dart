import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'data_table_config.dart';
import 'helpers/column_settings_service.dart';

/// Dialog for managing column visibility and ordering
class ColumnSettingsDialog extends StatefulWidget {
  final List<DataTableColumn> columns;
  final ColumnSettings currentSettings;
  final String tableTitle;

  const ColumnSettingsDialog({
    super.key,
    required this.columns,
    required this.currentSettings,
    this.tableTitle = 'Table',
  });

  @override
  State<ColumnSettingsDialog> createState() => _ColumnSettingsDialogState();
}

class _ColumnSettingsDialogState extends State<ColumnSettingsDialog> {
  late List<String> _visibleColumns;
  late List<String> _columnOrder;
  late Map<String, double> _columnWidths;
  late List<DataTableColumn> _columns; // Local copy of columns

  @override
  void initState() {
    super.initState();
    _visibleColumns = List.from(widget.currentSettings.visibleColumns);
    _columnOrder = List.from(widget.currentSettings.columnOrder);
    _columnWidths = Map.from(widget.currentSettings.columnWidths);
    _columns = List.from(widget.columns); // Create local copy
  }

  @override
  Widget build(BuildContext context) {
    final t = Localizations.of<AppLocalizations>(context, AppLocalizations)!;
    final theme = Theme.of(context);

    return Dialog(
      child: Container(
        width: MediaQuery.of(context).size.width * 0.8,
        height: MediaQuery.of(context).size.height * 0.7,
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Icon(
                  Icons.view_column,
                  color: theme.colorScheme.primary,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Text(
                  t.columnSettings,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              t.columnSettingsDescription,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            
            // Column list
            Expanded(
              child: _buildColumnList(t, theme),
            ),
            
            const SizedBox(height: 24),
            
            // Action buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _resetToDefaults,
                  child: Text(t.resetToDefaults),
                ),
                const SizedBox(width: 12),
                OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(t.cancel),
                ),
                const SizedBox(width: 12),
                FilledButton(
                  onPressed: _saveSettings,
                  child: Text(t.save),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildColumnList(AppLocalizations t, ThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(8),
                topRight: Radius.circular(8),
              ),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 24,
                  child: Checkbox(
                    value: _visibleColumns.length == _columns.length,
                    tristate: true,
                    onChanged: (value) {
                      if (value == true) {
                        setState(() {
                          _visibleColumns = _columns.map((col) => col.key).toList();
                        });
                      } else {
                        // Keep at least one column visible
                        setState(() {
                          _visibleColumns = [_columns.first.key];
                        });
                      }
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: Text(
                    t.columnName,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Expanded(
                  flex: 1,
                  child: Text(
                    t.visibility,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  t.order,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          
          // Column items
          Expanded(
            child: ReorderableListView.builder(
              itemCount: _columns.length,
              onReorder: _onReorder,
              itemBuilder: (context, index) {
                final column = _columns[index];
                final isVisible = _visibleColumns.contains(column.key);
                
                return Container(
                  key: ValueKey(column.key),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: theme.dividerColor.withValues(alpha: 0.5),
                      ),
                    ),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    leading: SizedBox(
                      width: 24,
                      child: Checkbox(
                        value: isVisible,
                        onChanged: (value) {
                          setState(() {
                            if (value == true) {
                              if (!_visibleColumns.contains(column.key)) {
                                _visibleColumns.add(column.key);
                              }
                            } else {
                              // Prevent hiding all columns
                              if (_visibleColumns.length > 1) {
                                _visibleColumns.remove(column.key);
                              }
                            }
                          });
                        },
                      ),
                    ),
                    title: Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                column.label,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              if (column.tooltip != null)
                                Text(
                                  column.tooltip!,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Expanded(
                          flex: 1,
                          child: Row(
                            children: [
                              Icon(
                                isVisible ? Icons.visibility : Icons.visibility_off,
                                size: 16,
                                color: isVisible 
                                    ? theme.colorScheme.primary 
                                    : theme.colorScheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                isVisible ? t.visible : t.hidden,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: isVisible 
                                      ? theme.colorScheme.primary 
                                      : theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          Icons.drag_handle,
                          size: 16,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _onReorder(int oldIndex, int newIndex) {
    setState(() {
      if (oldIndex < newIndex) {
        newIndex -= 1;
      }
      final column = _columns.removeAt(oldIndex);
      _columns.insert(newIndex, column);
      
      // Update column order
      _columnOrder = _columns.map((col) => col.key).toList();
    });
  }

  void _resetToDefaults() {
    setState(() {
      _visibleColumns = _columns.map((col) => col.key).toList();
      _columnOrder = _columns.map((col) => col.key).toList();
      _columnWidths.clear();
    });
  }

  void _saveSettings() {
    final newSettings = ColumnSettings(
      visibleColumns: _visibleColumns,
      columnOrder: _columnOrder,
      columnWidths: _columnWidths,
    );
    
    Navigator.of(context).pop(newSettings);
  }
}
