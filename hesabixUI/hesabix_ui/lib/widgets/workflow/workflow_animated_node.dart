import 'package:flutter/material.dart';
import '../../models/workflow_editor_models.dart';
import 'workflow_node_widget.dart';

/// Animated wrapper برای WorkflowNodeWidget
class WorkflowAnimatedNode extends StatelessWidget {
  final WorkflowNodeModel node;
  final bool isSelected;
  final VoidCallback? onTap;
  final ValueChanged<Offset>? onPositionChanged;
  final VoidCallback? onStartConnection;
  final VoidCallback? onEndConnection;
  final VoidCallback? onLongPress;

  const WorkflowAnimatedNode({
    super.key,
    required this.node,
    this.isSelected = false,
    this.onTap,
    this.onPositionChanged,
    this.onStartConnection,
    this.onEndConnection,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
      builder: (context, value, child) {
        return Transform.scale(
          scale: value,
          child: Opacity(
            opacity: value,
            child: WorkflowNodeWidget(
              node: node,
              isSelected: isSelected,
              onTap: onTap,
              onPositionChanged: onPositionChanged,
              onStartConnection: onStartConnection,
              onEndConnection: onEndConnection,
              onLongPress: onLongPress,
            ),
          ),
        );
      },
    );
  }
}

