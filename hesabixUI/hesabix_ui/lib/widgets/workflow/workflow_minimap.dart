import 'package:flutter/material.dart';
import '../../models/workflow_editor_models.dart';
import '../../models/workflow_editor_state.dart';

/// Mini-map برای نمایش نمای کلی workflow
class WorkflowMinimap extends StatelessWidget {
  final WorkflowEditorState state;
  final Size canvasSize;
  final Offset viewportOffset;
  final double zoomLevel;
  final Function(Offset)? onMinimapTap;

  const WorkflowMinimap({
    super.key,
    required this.state,
    required this.canvasSize,
    required this.viewportOffset,
    required this.zoomLevel,
    this.onMinimapTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isRtl = Directionality.of(context) == TextDirection.rtl;

    return Container(
      width: 200,
      height: 150,
      margin: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border.all(
          color: theme.dividerColor,
          width: 1,
        ),
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: CustomPaint(
          painter: MinimapPainter(
            nodes: state.nodes,
            connections: state.connections,
            canvasSize: canvasSize,
            viewportOffset: viewportOffset,
            zoomLevel: zoomLevel,
            theme: theme,
          ),
          child: GestureDetector(
            onTapDown: (details) {
              if (onMinimapTap != null) {
                final localPosition = details.localPosition;
                // تبدیل موقعیت mini-map به موقعیت canvas
                final scaleX = canvasSize.width / 200;
                final scaleY = canvasSize.height / 150;
                final canvasPosition = Offset(
                  localPosition.dx * scaleX - viewportOffset.dx,
                  localPosition.dy * scaleY - viewportOffset.dy,
                );
                onMinimapTap?.call(canvasPosition);
              }
            },
          ),
        ),
      ),
    );
  }
}

/// Painter برای رسم mini-map
class MinimapPainter extends CustomPainter {
  final List<WorkflowNodeModel> nodes;
  final List<WorkflowConnectionModel> connections;
  final Size canvasSize;
  final Offset viewportOffset;
  final double zoomLevel;
  final ThemeData theme;

  MinimapPainter({
    required this.nodes,
    required this.connections,
    required this.canvasSize,
    required this.viewportOffset,
    required this.zoomLevel,
    required this.theme,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (nodes.isEmpty) {
      // نمایش پیام خالی
      final textPainter = TextPainter(
        text: TextSpan(
          text: 'خالی',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        textDirection: TextDirection.rtl,
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(
          (size.width - textPainter.width) / 2,
          (size.height - textPainter.height) / 2,
        ),
      );
      return;
    }

    // محاسبه scale
    final minX = nodes.map((n) => n.position.dx).reduce((a, b) => a < b ? a : b);
    final maxX = nodes.map((n) => n.position.dx + 180).reduce((a, b) => a > b ? a : b);
    final minY = nodes.map((n) => n.position.dy).reduce((a, b) => a < b ? a : b);
    final maxY = nodes.map((n) => n.position.dy + 100).reduce((a, b) => a > b ? a : b);

    final width = maxX - minX;
    final height = maxY - minY;

    final scaleX = size.width / (width > 0 ? width : canvasSize.width);
    final scaleY = size.height / (height > 0 ? height : canvasSize.height);
    final scale = (scaleX < scaleY ? scaleX : scaleY) * 0.9; // 90% برای padding

    final offsetX = (size.width - width * scale) / 2 - minX * scale;
    final offsetY = (size.height - height * scale) / 2 - minY * scale;

    // رسم connections
    final connectionPaint = Paint()
      ..color = Colors.blue.shade300
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    for (final conn in connections) {
      final sourceNode = nodes.firstWhere(
        (n) => n.id == conn.sourceNodeId,
        orElse: () => nodes.first,
      );
      final targetNode = nodes.firstWhere(
        (n) => n.id == conn.targetNodeId,
        orElse: () => nodes.first,
      );

      final sourcePos = Offset(
        sourceNode.position.dx * scale + offsetX,
        sourceNode.position.dy * scale + offsetY,
      );
      final targetPos = Offset(
        targetNode.position.dx * scale + offsetX,
        targetNode.position.dy * scale + offsetY,
      );

      canvas.drawLine(sourcePos, targetPos, connectionPaint);
    }

    // رسم nodes
    for (final node in nodes) {
      final color = _getNodeColor(node.type);
      final nodePaint = Paint()
        ..color = color
        ..style = PaintingStyle.fill;

      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          node.position.dx * scale + offsetX,
          node.position.dy * scale + offsetY,
          180 * scale,
          100 * scale,
        ),
        Radius.circular(4 * scale),
      );

      canvas.drawRRect(rect, nodePaint);
    }

    // رسم viewport rectangle
    final viewportPaint = Paint()
      ..color = theme.colorScheme.primary.withOpacity(0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    final viewportRect = Rect.fromLTWH(
      -viewportOffset.dx * scale + offsetX,
      -viewportOffset.dy * scale + offsetY,
      size.width / zoomLevel * scale,
      size.height / zoomLevel * scale,
    );

    canvas.drawRect(viewportRect, viewportPaint);
  }

  Color _getNodeColor(WorkflowNodeType type) {
    switch (type) {
      case WorkflowNodeType.trigger:
        return Colors.green;
      case WorkflowNodeType.action:
        return theme.colorScheme.primary;
      case WorkflowNodeType.condition:
        return Colors.orange;
      case WorkflowNodeType.loop:
        return Colors.purple;
    }
  }

  @override
  bool shouldRepaint(MinimapPainter oldDelegate) {
    return oldDelegate.nodes != nodes ||
        oldDelegate.connections != connections ||
        oldDelegate.viewportOffset != viewportOffset ||
        oldDelegate.zoomLevel != zoomLevel;
  }
}

