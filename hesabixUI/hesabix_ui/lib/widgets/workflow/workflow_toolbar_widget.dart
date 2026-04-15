import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';
import '../../models/workflow_editor_state.dart';
import '../../utils/workflow_auto_layout.dart';
import '../../utils/workflow_responsive.dart';
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
  final VoidCallback? onSaveAsTemplate;
  final VoidCallback? onLoadTemplate;

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
    this.onSaveAsTemplate,
    this.onLoadTemplate,
  });

  static void _showValidationErrors(BuildContext context, WorkflowEditorState state) {
    final errors = state.getAllValidationErrors();
    final t = AppLocalizations.of(context);
    
    if (errors.isEmpty) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.green),
              const SizedBox(width: 8),
              Text(t.workflowValidationSuccess),
            ],
          ),
          content: Text(t.workflowAllNodesValid),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(t.workflowClose ?? 'بستن'),
            ),
          ],
        ),
      );
      return;
    }
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.error, color: Colors.red),
            const SizedBox(width: 8),
            Text(t.workflowNodesWithErrors(errors.length)),
          ],
        ),
        content: SizedBox(
          width: 400,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: errors.entries.map((entry) {
                final node = state.getNodeById(entry.key);
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.error, color: Colors.red, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                node?.label ?? AppLocalizations.of(context).workflowNodeUnknown,
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ...entry.value.map((error) => Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('• ', style: TextStyle(color: Colors.red)),
                              Expanded(child: Text(error)),
                            ],
                          ),
                        )),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(t.workflowClose ?? 'بستن'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final isDesktop = WorkflowResponsive.isDesktop(context);
    final toolbarRow = Row(
      mainAxisSize: isDesktop ? MainAxisSize.max : MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Tooltip(
          message: t.workflowToolbarOpenPalette,
          child: IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        const SizedBox(width: 8),
        // Zoom Controls
        Tooltip(
          message: t.workflowToolbarZoomOut,
          child: IconButton(
            icon: const Icon(Icons.zoom_out),
            onPressed: () {
              final newZoom = (state.zoomLevel - 0.1).clamp(0.5, 3.0);
              state.updateZoom(newZoom);
            },
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceVariant,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '${(state.zoomLevel * 100).toInt()}%',
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Tooltip(
          message: t.workflowToolbarZoomIn,
          child: IconButton(
            icon: const Icon(Icons.zoom_in),
            onPressed: () {
              final newZoom = (state.zoomLevel + 0.1).clamp(0.5, 3.0);
              state.updateZoom(newZoom);
            },
          ),
        ),
        Tooltip(
          message: t.workflowToolbarResetZoom,
          child: IconButton(
            icon: const Icon(Icons.fit_screen),
            onPressed: () {
              state.updateZoom(1.0);
            },
          ),
        ),
        const VerticalDivider(),
        Tooltip(
          message: t.workflowToolbarConnectionHelp,
          child: IconButton(
            icon: const Icon(Icons.help_outline),
            onPressed: () {
              WorkflowConnectionHelpDialog.show(context);
            },
          ),
        ),
        const VerticalDivider(),
        Tooltip(
          message: state.showGrid ? t.workflowToolbarHideGrid : t.workflowToolbarShowGrid,
          child: IconButton(
            icon: Icon(state.showGrid ? Icons.grid_4x4 : Icons.grid_off),
            color: state.showGrid ? theme.colorScheme.primary : null,
            onPressed: () {
              state.setShowGrid(!state.showGrid);
            },
          ),
        ),
        Tooltip(
          message: state.snapToGrid ? t.workflowToolbarDisableSnapToGrid : t.workflowToolbarEnableSnapToGrid,
          child: IconButton(
            icon: Icon(state.snapToGrid ? Icons.grid_on : Icons.grid_3x3),
            color: state.snapToGrid ? theme.colorScheme.primary : null,
            onPressed: () {
              state.setSnapToGrid(!state.snapToGrid);
            },
          ),
        ),
        const SizedBox(width: 8),
        // Alignment Tools (فقط وقتی چند نود انتخاب شده باشد)
        if (state.selectedNodeIds.length >= 2)
          PopupMenuButton(
            tooltip: t.workflowToolbarAlignmentTools,
            icon: const Icon(Icons.align_horizontal_left),
            itemBuilder: (context) {
              final items = <PopupMenuEntry<dynamic>>[
                PopupMenuItem(
                  child: Row(
                    children: [
                      const Icon(Icons.align_horizontal_left, size: 20),
                      const SizedBox(width: 8),
                      Text(t.workflowToolbarAlignLeft),
                    ],
                  ),
                  onTap: () => state.alignNodesLeft(),
                ),
                PopupMenuItem(
                  child: Row(
                    children: [
                      const Icon(Icons.align_horizontal_right, size: 20),
                      const SizedBox(width: 8),
                      Text(t.workflowToolbarAlignRight),
                    ],
                  ),
                  onTap: () => state.alignNodesRight(),
                ),
                PopupMenuItem(
                  child: Row(
                    children: [
                      const Icon(Icons.align_vertical_top, size: 20),
                      const SizedBox(width: 8),
                      Text(t.workflowToolbarAlignTop),
                    ],
                  ),
                  onTap: () => state.alignNodesTop(),
                ),
                PopupMenuItem(
                  child: Row(
                    children: [
                      const Icon(Icons.align_vertical_bottom, size: 20),
                      const SizedBox(width: 8),
                      Text(t.workflowToolbarAlignBottom),
                    ],
                  ),
                  onTap: () => state.alignNodesBottom(),
                ),
              ];

              if (state.selectedNodeIds.length >= 3) {
                items.add(const PopupMenuDivider());
                items.add(
                  PopupMenuItem(
                    child: Row(
                      children: [
                        const Icon(Icons.horizontal_distribute, size: 20),
                        const SizedBox(width: 8),
                        Text(t.workflowToolbarDistributeHorizontally),
                      ],
                    ),
                    onTap: () => state.distributeNodesHorizontally(),
                  ),
                );
                items.add(
                  PopupMenuItem(
                    child: Row(
                      children: [
                        const Icon(Icons.vertical_distribute, size: 20),
                        const SizedBox(width: 8),
                        Text(t.workflowToolbarDistributeVertically),
                      ],
                    ),
                    onTap: () => state.distributeNodesVertically(),
                  ),
                );
              }

              items.add(const PopupMenuDivider());
              items.add(
                PopupMenuItem(
                  child: Row(
                    children: [
                      const Icon(Icons.grid_on, size: 20),
                      const SizedBox(width: 8),
                      Text(t.workflowToolbarAlignToGrid),
                    ],
                  ),
                  onTap: () => state.alignSelectedNodesToGrid(),
                ),
              );

              return items;
            },
          ),
        if (state.selectedNodeIds.length >= 2) const SizedBox(width: 8),
        const VerticalDivider(),
        Tooltip(
          message: t.workflowToolbarClearAll,
          child: IconButton(
            icon: const Icon(Icons.cleaning_services),
            onPressed: onClear,
          ),
        ),
        const SizedBox(width: 8),
        Tooltip(
          message: t.workflowToolbarAutoLayout,
          child: IconButton(
            icon: const Icon(Icons.auto_awesome),
            onPressed: onAutoLayout,
          ),
        ),
        const SizedBox(width: 8),
        // Templates Menu
        PopupMenuButton(
          tooltip: t.workflowToolbarTemplates,
          icon: const Icon(Icons.save_alt),
          itemBuilder: (context) => [
            PopupMenuItem(
              child: Row(
                children: [
                  const Icon(Icons.save, size: 20),
                  const SizedBox(width: 8),
                  Text(t.workflowSaveAsTemplate),
                ],
              ),
              onTap: onSaveAsTemplate,
            ),
            PopupMenuItem(
              child: Row(
                children: [
                  const Icon(Icons.folder_open, size: 20),
                  const SizedBox(width: 8),
                  Text(t.workflowToolbarLoadTemplate),
                ],
              ),
              onTap: onLoadTemplate,
            ),
          ],
        ),
        const SizedBox(width: 8),
        PopupMenuButton<WorkflowAutoLayoutType>(
          tooltip: t.workflowToolbarSelectLayoutType,
          onSelected: onLayoutTypeChanged,
          itemBuilder: (_) => WorkflowAutoLayoutType.values
              .map(
                (type) => PopupMenuItem<WorkflowAutoLayoutType>(
                  value: type,
                  child: Text(
                    type == WorkflowAutoLayoutType.hierarchical
                        ? t.workflowToolbarHierarchical
                        : t.workflowToolbarForceDirected,
                  ),
                ),
              )
              .toList(),
          child: Chip(
            label: Text(
              layoutType == WorkflowAutoLayoutType.hierarchical
                  ? t.workflowToolbarHierarchical
                  : t.workflowToolbarForceDirected,
            ),
            avatar: const Icon(Icons.view_quilt, size: 16),
          ),
        ),
        const VerticalDivider(),
        Tooltip(
          message: t.workflowToolbarShowValidationErrors,
          child: IconButton(
            icon: Badge(
              label: Text('${state.getAllValidationErrors().length}'),
              isLabelVisible: state.getAllValidationErrors().isNotEmpty,
              child: const Icon(Icons.warning_amber),
            ),
            color: state.getAllValidationErrors().isNotEmpty ? Colors.orange : null,
            onPressed: () {
              _showValidationErrors(context, state);
            },
          ),
        ),
        const VerticalDivider(),
        Tooltip(
          message: t.workflowToolbarUndo,
          child: IconButton(
            icon: const Icon(Icons.undo),
            onPressed: state.canUndo ? onUndo : null,
          ),
        ),
        Tooltip(
          message: t.workflowToolbarRedo,
          child: IconButton(
            icon: const Icon(Icons.redo),
            onPressed: state.canRedo ? onRedo : null,
          ),
        ),
        if (isDesktop) const Spacer() else const SizedBox(width: 24),
        Text(
          t.workflowToolbarNodes,
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
          t.workflowToolbarConnections,
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
        if (!isDesktop) const SizedBox(width: 16),
      ],
    );

    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          bottom: BorderSide(color: theme.dividerColor),
        ),
      ),
      child: isDesktop
          ? toolbarRow
          : SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: toolbarRow,
            ),
    );
  }
}

