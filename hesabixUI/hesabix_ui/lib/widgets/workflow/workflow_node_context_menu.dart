import 'package:flutter/material.dart';
import '../../models/workflow_editor_models.dart';

/// Context Menu برای node ها
class WorkflowNodeContextMenu extends StatelessWidget {
  final WorkflowNodeModel node;
  final VoidCallback? onEdit;
  final VoidCallback? onDuplicate;
  final VoidCallback? onDelete;
  final VoidCallback? onEditComment;

  const WorkflowNodeContextMenu({
    super.key,
    required this.node,
    this.onEdit,
    this.onDuplicate,
    this.onDelete,
    this.onEditComment,
  });

  static Future<String?> show(
    BuildContext context,
    Offset position, {
    required WorkflowNodeModel node,
    VoidCallback? onEdit,
    VoidCallback? onDuplicate,
    VoidCallback? onDelete,
    VoidCallback? onEditComment,
  }) async {
    final result = await showMenu<String>(
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
        ),
        PopupMenuItem<String>(
          value: 'comment',
          child: ListTile(
            leading: Icon(
              node.comment != null && node.comment!.isNotEmpty 
                  ? Icons.edit_note 
                  : Icons.note_add,
            ),
            title: Text(
              node.comment != null && node.comment!.isNotEmpty 
                  ? 'ویرایش یادداشت' 
                  : 'افزودن یادداشت',
            ),
            contentPadding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
          ),
        ),
        PopupMenuItem<String>(
          value: 'duplicate',
          child: ListTile(
            leading: const Icon(Icons.copy),
            title: const Text('کپی'),
            contentPadding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'delete',
          child: ListTile(
            leading: const Icon(Icons.delete, color: Colors.red),
            title: const Text('حذف', style: TextStyle(color: Colors.red)),
            contentPadding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
          ),
        ),
      ],
    );

    // بعد از بسته شدن menu، callback مناسب را اجرا می‌کنیم
    if (result != null) {
      // کمی تأخیر برای اطمینان از بسته شدن کامل menu
      await Future.delayed(const Duration(milliseconds: 100));
      
      switch (result) {
        case 'edit':
          onEdit?.call();
          break;
        case 'comment':
          onEditComment?.call();
          break;
        case 'duplicate':
          onDuplicate?.call();
          break;
        case 'delete':
          onDelete?.call();
          break;
      }
    }
    
    return result;
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

