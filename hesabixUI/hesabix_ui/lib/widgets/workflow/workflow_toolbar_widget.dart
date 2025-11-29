import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';
import '../../models/workflow_editor_state.dart';
import '../../utils/workflow_auto_layout.dart';
import 'workflow_connection_help_dialog.dart';

/// Toolbar برای workflow editor
class WorkflowToolbarWidget extends StatelessWidget {
  final WorkflowEditorState state;
  final VoidCallback? onClear;
  final VoidCallback? onAutoLayout;
  final VoidCallback? onValidate;
  final VoidCallback? onUndo;
  final VoidCallback? onRedo;
  final WorkflowAutoLayoutType layoutType;
  final ValueChanged<WorkflowAutoLayoutType>? onLayoutTypeChanged;

  const WorkflowToolbarWidget({
    super.key,
    required this.state,
    this.onClear,
    this.onAutoLayout,
    this.onValidate,
    this.onUndo,
    this.onRedo,
    this.onLayoutTypeChanged,
    this.layoutType = WorkflowAutoLayoutType.hierarchical,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);

    String _localizedText(String faText, String enText) {
      return t.localeName.startsWith('fa') ? faText : enText;
    }

    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          bottom: BorderSide(color: theme.dividerColor),
        ),
      ),
      child: Row(
        children: [
          Tooltip(
            message: _localizedText('باز کردن پالت node ها', 'Open node palette'),
            child: IconButton(
              icon: const Icon(Icons.menu),
              onPressed: () => Scaffold.of(context).openDrawer(),
            ),
          ),
          const SizedBox(width: 8),
          Tooltip(
            message: _localizedText('راهنمای اتصال نودها', 'Connection help'),
            child: IconButton(
              icon: const Icon(Icons.help_outline),
              onPressed: () {
                WorkflowConnectionHelpDialog.show(context);
              },
            ),
          ),
          const VerticalDivider(),
          Tooltip(
            message: _localizedText(
              state.snapToGrid ? 'غیرفعال کردن Snap to Grid' : 'فعال کردن Snap to Grid',
              state.snapToGrid ? 'Disable Snap to Grid' : 'Enable Snap to Grid',
            ),
            child: IconButton(
              icon: Icon(state.snapToGrid ? Icons.grid_on : Icons.grid_off),
              color: state.snapToGrid ? Theme.of(context).colorScheme.primary : null,
              onPressed: () {
                state.setSnapToGrid(!state.snapToGrid);
              },
            ),
          ),
          const SizedBox(width: 8),
          Tooltip(
            message: _localizedText('پاکسازی همه', 'Clear all'),
            child: IconButton(
              icon: const Icon(Icons.cleaning_services),
              onPressed: onClear,
            ),
          ),
          const SizedBox(width: 8),
          Tooltip(
            message: _localizedText('چیدمان خودکار', 'Auto layout'),
            child: IconButton(
              icon: const Icon(Icons.auto_awesome),
              onPressed: onAutoLayout,
            ),
          ),
          const SizedBox(width: 8),
          PopupMenuButton<WorkflowAutoLayoutType>(
            tooltip: _localizedText('انتخاب نوع چیدمان', 'Select layout type'),
            onSelected: onLayoutTypeChanged,
            itemBuilder: (_) => WorkflowAutoLayoutType.values
                .map(
                  (type) => PopupMenuItem<WorkflowAutoLayoutType>(
                    value: type,
                    child: Text(
                      type == WorkflowAutoLayoutType.hierarchical
                          ? _localizedText('لایه‌ای (Hierarchical)', 'Hierarchical')
                          : _localizedText('نیرویی (Force-directed)', 'Force directed'),
                    ),
                  ),
                )
                .toList(),
            child: Chip(
              label: Text(
                layoutType == WorkflowAutoLayoutType.hierarchical
                    ? _localizedText('Hierarchical', 'Hierarchical')
                    : _localizedText('Force-directed', 'Force-directed'),
              ),
              avatar: const Icon(Icons.view_quilt, size: 16),
            ),
          ),
          const VerticalDivider(),
          Tooltip(
            message: _localizedText('بازگردانی', 'Undo'),
            child: IconButton(
              icon: const Icon(Icons.undo),
              onPressed: state.canUndo ? onUndo : null,
            ),
          ),
          Tooltip(
            message: _localizedText('انجام مجدد', 'Redo'),
            child: IconButton(
              icon: const Icon(Icons.redo),
              onPressed: state.canRedo ? onRedo : null,
            ),
          ),
          const Spacer(),
          Text(
            _localizedText('Nodeها', 'Nodes'),
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(width: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '${state.nodes.length}',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Text(
            _localizedText('اتصالات', 'Connections'),
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(width: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: theme.colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '${state.connections.length}',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSecondaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

