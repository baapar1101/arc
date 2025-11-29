import 'package:flutter/material.dart';
import '../../models/workflow_editor_models.dart';
import '../../utils/workflow_constants.dart';

/// Widget برای نمایش یک node در workflow
class WorkflowNodeWidget extends StatelessWidget {
  final WorkflowNodeModel node;
  final bool isSelected;
  final VoidCallback? onTap;
  final ValueChanged<Offset>? onPositionChanged;
  final VoidCallback? onStartConnection;
  final VoidCallback? onEndConnection;
  final VoidCallback? onLongPress;
  final ValueChanged<Offset>? onConnectionDragUpdate;
  final double zoomLevel;
  final bool highlightConnectionPoints; // برای highlight کردن connection points قابل اتصال
  final ValueChanged<Offset>? onDeltaChanged; // برای ارسال delta در canvas coordinates

  const WorkflowNodeWidget({
    super.key,
    required this.node,
    this.isSelected = false,
    this.onTap,
    this.onPositionChanged,
    this.onStartConnection,
    this.onEndConnection,
    this.onLongPress,
    this.onConnectionDragUpdate,
    this.zoomLevel = 1.0,
    this.highlightConnectionPoints = false,
    this.onDeltaChanged,
  });

  @override
  Widget build(BuildContext context) {
    try {
      final theme = Theme.of(context);
      final color = _getNodeColor(node.type, theme);

      // بررسی اعتبار موقعیت
      final validPosition = _isValidPosition(node.position) 
          ? node.position 
          : const Offset(200, 200);
      
      // بررسی اعتبار zoomLevel
      final validZoomLevel = (zoomLevel > 0 && zoomLevel.isFinite && !zoomLevel.isNaN) 
          ? zoomLevel 
          : 1.0;

      return Positioned(
        left: validPosition.dx,
        top: validPosition.dy,
      child: RepaintBoundary(
        child: GestureDetector(
          onTap: onTap,
          onLongPress: onLongPress,
          onPanStart: (details) {
            // ذخیره موقعیت اولیه برای محاسبه delta
            if (onDeltaChanged != null) {
              final RenderBox? box = context.findRenderObject() as RenderBox?;
              if (box != null) {
                final globalPosition = box.localToGlobal(details.localPosition);
                onDeltaChanged?.call(globalPosition);
              }
            }
          },
          onPanUpdate: (details) {
            if (onDeltaChanged != null) {
              // ارسال موقعیت global برای محاسبه delta در parent
              final RenderBox? box = context.findRenderObject() as RenderBox?;
              if (box != null) {
                final globalPosition = box.localToGlobal(details.localPosition);
                onDeltaChanged?.call(globalPosition);
              }
            } else {
              // Fallback: استفاده از delta با zoom adjustment
              final validZoom = (zoomLevel > 0 && zoomLevel.isFinite) ? zoomLevel : 1.0;
              final adjustedDelta = details.delta / validZoom;
              final newPosition = node.position + adjustedDelta;
              if (_isValidPosition(newPosition)) {
                onPositionChanged?.call(newPosition);
              }
            }
          },
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // نود اصلی
              Container(
                width: WorkflowConstants.nodeWidth,
                height: WorkflowConstants.nodeHeight,
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  border: Border.all(
                    color: isSelected ? theme.colorScheme.primary : color,
                    width: isSelected ? 3 : 2,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header با رنگ
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.2),
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(12),
                          topRight: Radius.circular(12),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _getNodeIcon(node.type),
                            size: 18,
                            color: color,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              node.label,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: color,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Body
                    const Expanded(
                      child: SizedBox(),
                    ),
                  ],
                ),
              ),
              // Connection points در اطراف نود
              // بالا (input) - فقط برای action/condition/loop
              if (node.type != WorkflowNodeType.trigger)
                Positioned(
                  top: -8,
                  left: WorkflowConstants.nodeWidth / 2 - 8, // وسط نود
                  child: _buildConnectionPoint(
                    context,
                    ConnectionPointType.input,
                    isHighlighted: highlightConnectionPoints,
                    onTap: onEndConnection,
                    onConnectionDragUpdate: onConnectionDragUpdate,
                  ),
                ),
              // پایین (output) - برای همه
              Positioned(
                bottom: -8,
                left: WorkflowConstants.nodeWidth / 2 - 8, // وسط نود
                child: _buildConnectionPoint(
                  context,
                  ConnectionPointType.output,
                  isHighlighted: false, // output نباید highlight شود
                  onTap: onStartConnection,
                  onConnectionDragUpdate: onConnectionDragUpdate,
                ),
              ),
              // راست (output) - فقط برای action/condition/loop
              if (node.type != WorkflowNodeType.trigger)
                Positioned(
                  top: WorkflowConstants.nodeHeight / 2 - 8, // وسط نود
                  right: -8,
                  child: _buildConnectionPoint(
                    context,
                    ConnectionPointType.output,
                    isHighlighted: false,
                    onTap: onStartConnection,
                    onConnectionDragUpdate: onConnectionDragUpdate,
                  ),
                ),
              // چپ (input) - فقط برای trigger
              if (node.type == WorkflowNodeType.trigger)
                Positioned(
                  top: WorkflowConstants.nodeHeight / 2 - 8, // وسط نود
                  left: -8,
                  child: _buildConnectionPoint(
                    context,
                    ConnectionPointType.input,
                    isHighlighted: highlightConnectionPoints,
                    onTap: onEndConnection,
                    onConnectionDragUpdate: onConnectionDragUpdate,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    } catch (e, stackTrace) {
      // در صورت خطا، یک widget placeholder برگردان
      debugPrint('خطا در ساخت WorkflowNodeWidget برای node ${node.id}: $e');
      debugPrint('StackTrace: $stackTrace');
      return Positioned(
        left: _isValidPosition(node.position) ? node.position.dx : 200,
        top: _isValidPosition(node.position) ? node.position.dy : 200,
        child: Container(
          width: 180,
          height: 100,
          color: Colors.red.withOpacity(0.2),
          child: const Center(
            child: Icon(Icons.error, color: Colors.red),
          ),
        ),
      );
    }
  }

  /// بررسی اعتبار یک موقعیت
  bool _isValidPosition(Offset position) {
    return position.dx.isFinite && 
           position.dy.isFinite &&
           !position.dx.isNaN && 
           !position.dy.isNaN;
  }

  Widget _buildConnectionPoint(
    BuildContext context,
    ConnectionPointType type, {
    bool isHighlighted = false,
    VoidCallback? onTap,
    ValueChanged<Offset>? onConnectionDragUpdate,
  }) {
    final theme = Theme.of(context);
    final isOutput = type == ConnectionPointType.output;

    return GestureDetector(
      onPanStart: (details) {
        if (isOutput && onTap != null) {
          onTap(); // شروع اتصال از output point
        }
      },
      onPanUpdate: (details) {
        if (isOutput && onConnectionDragUpdate != null) {
          final RenderBox? box = context.findRenderObject() as RenderBox?;
          if (box != null) {
            final localToGlobal = box.localToGlobal(details.localPosition);
            onConnectionDragUpdate(localToGlobal);
          }
        }
      },
      onPanEnd: (details) {
        if (!isOutput && onTap != null) {
          onTap(); // کامل کردن اتصال در input point
        }
      },
      child: MouseRegion(
        cursor: isOutput ? SystemMouseCursors.grab : SystemMouseCursors.click,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: isHighlighted ? WorkflowConstants.connectionPointHighlightSize : WorkflowConstants.connectionPointSize,
          height: isHighlighted ? WorkflowConstants.connectionPointHighlightSize : WorkflowConstants.connectionPointSize,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isHighlighted ? Colors.green : theme.colorScheme.primary,
            border: Border.all(
              color: theme.colorScheme.surface,
              width: isHighlighted ? 3 : 2,
            ),
            boxShadow: [
              BoxShadow(
                color: (isHighlighted ? Colors.green : Colors.black).withOpacity(isHighlighted ? 0.5 : 0.2),
                blurRadius: isHighlighted ? 8 : 4,
                offset: const Offset(0, 2),
                spreadRadius: isHighlighted ? 2 : 0,
              ),
            ],
          ),
          alignment: Alignment.center,
          child: Container(
            width: isHighlighted ? 10 : 8,
            height: isHighlighted ? 10 : 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: theme.colorScheme.surface,
            ),
          ),
        ),
      ),
    );
  }

  Color _getNodeColor(WorkflowNodeType type, ThemeData theme) {
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

  IconData _getNodeIcon(WorkflowNodeType type) {
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
