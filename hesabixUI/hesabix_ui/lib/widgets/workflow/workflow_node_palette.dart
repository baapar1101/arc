import 'package:flutter/material.dart';
import '../../models/workflow_editor_models.dart';

/// پالت node های قابل افزودن به workflow
class WorkflowNodePalette extends StatelessWidget {
  final List<WorkflowNodeMetadata> triggers;
  final List<WorkflowNodeMetadata> actions;
  final Function(WorkflowNodeType type, String key, String name) onNodeSelected;

  const WorkflowNodePalette({
    super.key,
    required this.triggers,
    required this.actions,
    required this.onNodeSelected,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isRtl = Directionality.of(context) == TextDirection.rtl;

    return Drawer(
      width: 300,
      child: WorkflowNodePaletteContent(
        triggers: triggers,
        actions: actions,
        onNodeSelected: onNodeSelected,
      ),
    );
  }
}

/// محتوای پالت node ها (بدون Drawer wrapper)
class WorkflowNodePaletteContent extends StatelessWidget {
  final List<WorkflowNodeMetadata> triggers;
  final List<WorkflowNodeMetadata> actions;
  final Function(WorkflowNodeType type, String key, String name) onNodeSelected;

  const WorkflowNodePaletteContent({
    super.key,
    required this.triggers,
    required this.actions,
    required this.onNodeSelected,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isRtl = Directionality.of(context) == TextDirection.rtl;

    return Column(
      children: [
        // Header
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer,
            border: Border(
              bottom: BorderSide(color: theme.dividerColor),
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.view_list, color: theme.colorScheme.onPrimaryContainer),
              const SizedBox(width: 12),
              Text(
                'Node ها',
                style: theme.textTheme.titleLarge?.copyWith(
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
            ],
          ),
        ),
        // Content
        Expanded(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              // Triggers Section
              _buildSection(
                context,
                title: 'Trigger ها',
                icon: Icons.bolt,
                color: Colors.green,
                items: triggers,
                type: WorkflowNodeType.trigger,
              ),
              // Actions Section
              _buildSection(
                context,
                title: 'Action ها',
                icon: Icons.play_arrow,
                color: theme.colorScheme.primary,
                items: actions,
                type: WorkflowNodeType.action,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSection(
    BuildContext context, {
    required String title,
    required IconData icon,
    required Color color,
    required List<WorkflowNodeMetadata> items,
    required WorkflowNodeType type,
  }) {
    final theme = Theme.of(context);
    final isExpanded = true; // در آینده می‌توان stateful کرد

    return Theme(
      data: theme.copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        leading: Icon(icon, color: color),
        title: Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        initiallyExpanded: isExpanded,
        children: items.isEmpty
            ? [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'هیچ ${title.toLowerCase()}ی یافت نشد',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ]
            : items.map((item) {
                return _buildPaletteItem(context, item, type, color);
              }).toList(),
      ),
    );
  }

  Widget _buildPaletteItem(
    BuildContext context,
    WorkflowNodeMetadata item,
    WorkflowNodeType type,
    Color color,
  ) {
    final theme = Theme.of(context);

    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: color.withOpacity(0.2),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          _getIconForType(type),
          color: color,
          size: 20,
        ),
      ),
      title: Text(
        item.name,
        style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: item.description != null && item.description!.isNotEmpty
          ? Text(
              item.description!,
              style: theme.textTheme.bodySmall,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            )
          : null,
      trailing: Icon(
        Icons.drag_handle,
        color: theme.colorScheme.onSurfaceVariant,
        size: 20,
      ),
      onTap: () {
        onNodeSelected(type, item.key, item.name);
      },
    );
  }

  IconData _getIconForType(WorkflowNodeType type) {
    switch (type) {
      case WorkflowNodeType.trigger:
        return Icons.bolt;
      case WorkflowNodeType.action:
        return Icons.play_arrow;
      case WorkflowNodeType.condition:
        return Icons.code;
      case WorkflowNodeType.loop:
        return Icons.loop;
    }
  }
}


