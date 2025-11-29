import 'package:flutter/material.dart';
import '../../models/workflow_editor_models.dart';

/// Context Menu برای node ها
class WorkflowNodeContextMenu extends StatelessWidget {
  final WorkflowNodeModel node;
  final VoidCallback? onEdit;
  final VoidCallback? onDuplicate;
  final VoidCallback? onDelete;

  const WorkflowNodeContextMenu({
    super.key,
    required this.node,
    this.onEdit,
    this.onDuplicate,
    this.onDelete,
  });

  static Future<String?> show(
    BuildContext context,
    Offset position, {
    required WorkflowNodeModel node,
    VoidCallback? onEdit,
    VoidCallback? onDuplicate,
    VoidCallback? onDelete,
  }) async {
    return showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      items: [
        PopupMenuItem<String>(
          value: 'edit',
          child: ListTile(
            leading: const Icon(Icons.edit),
            title: const Text('ویرایش'),
            contentPadding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
          ),
          onTap: () => onEdit?.call(),
        ),
        PopupMenuItem<String>(
          value: 'duplicate',
          child: ListTile(
            leading: const Icon(Icons.copy),
            title: const Text('کپی'),
            contentPadding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
          ),
          onTap: () => onDuplicate?.call(),
        ),
        PopupMenuItem<String>(
          value: 'delete',
          child: ListTile(
            leading: const Icon(Icons.delete, color: Colors.red),
            title: const Text('حذف', style: TextStyle(color: Colors.red)),
            contentPadding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
          ),
          onTap: () => onDelete?.call(),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'edit',
          child: ListTile(
            leading: const Icon(Icons.edit),
            title: const Text('ویرایش'),
            contentPadding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
          ),
          onTap: () => Future.delayed(Duration.zero, () => onEdit?.call()),
        ),
        PopupMenuItem(
          value: 'duplicate',
          child: ListTile(
            leading: const Icon(Icons.copy),
            title: const Text('کپی'),
            contentPadding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
          ),
          onTap: () => Future.delayed(Duration.zero, () => onDuplicate?.call()),
        ),
        PopupMenuItem(
          value: 'delete',
          child: ListTile(
            leading: const Icon(Icons.delete, color: Colors.red),
            title: const Text('حذف', style: TextStyle(color: Colors.red)),
            contentPadding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
          ),
          onTap: () => Future.delayed(Duration.zero, () => onDelete?.call()),
        ),
      ],
    );
  }
}

