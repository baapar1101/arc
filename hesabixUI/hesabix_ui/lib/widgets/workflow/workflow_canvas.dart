import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../models/workflow_editor_models.dart';
import '../../models/workflow_editor_state.dart';
import '../../utils/workflow_constants.dart';
import 'workflow_connection_painter.dart';
import 'workflow_node_widget.dart';

/// Canvas اصلی برای نمایش و ویرایش workflow
class WorkflowCanvas extends StatefulWidget {
  final WorkflowEditorState state;
  final Function(WorkflowNodeModel)? onNodeTap;
  final Function(WorkflowConnectionModel)? onConnectionTap;
  final Function(WorkflowNodeModel, Offset)? onNodeLongPress;

  const WorkflowCanvas({
    super.key,
    required this.state,
    this.onNodeTap,
    this.onConnectionTap,
    this.onNodeLongPress,
  });

  @override
  State<WorkflowCanvas> createState() => _WorkflowCanvasState();
}

class _WorkflowCanvasState extends State<WorkflowCanvas> {
  late TransformationController _transformationController;
  Offset? _lastPanPosition;
  Offset? _connectingToPosition;
  final GlobalKey _canvasKey = GlobalKey();
  final GlobalKey _interactiveViewerKey = GlobalKey();
  Offset? _dragStartPosition; // موقعیت شروع drag در canvas coordinates
  String? _draggingNodeId; // ID نودی که در حال drag است

  @override
  void initState() {
    super.initState();
    _transformationController = TransformationController();
    widget.state.addListener(_onStateChanged);
  }

  @override
  void dispose() {
    widget.state.removeListener(_onStateChanged);
    _transformationController.dispose();
    super.dispose();
  }

  void _onStateChanged() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    try {
      // محاسبه موقعیت node ها (با در نظر گیری zoom و pan)
      final nodePositions = <String, Offset>{};
      for (final node in widget.state.nodes) {
        // بررسی اعتبار موقعیت
        if (_isValidPosition(node.position)) {
          nodePositions[node.id] = node.position;
        } else {
          // اگر موقعیت نامعتبر است، از موقعیت پیش‌فرض استفاده کن
          debugPrint('موقعیت نامعتبر برای node ${node.id}: ${node.position}');
          nodePositions[node.id] = const Offset(200, 200);
        }
      }

      // محاسبه موقعیت اتصال موقتی
      Offset? connectingFrom;
      Offset? connectingTo;
      if (widget.state.isConnecting) {
        final fromNode = widget.state.getNodeById(widget.state.connectingFromNodeId ?? '');
        if (fromNode != null && _isValidPosition(fromNode.position)) {
          // استفاده از connection point در پایین node
          connectingFrom = WorkflowConstants.getConnectionPoint(fromNode.position, 'bottom');
        }
        final connectingPos = widget.state.connectingPosition ?? _connectingToPosition;
        if (connectingPos != null && _isValidPosition(connectingPos)) {
          connectingTo = connectingPos;
        }
      }

    return InteractiveViewer(
      key: _interactiveViewerKey,
      transformationController: _transformationController,
      minScale: WorkflowConstants.minZoom,
      maxScale: WorkflowConstants.maxZoom,
      panEnabled: !widget.state.isConnecting, // غیرفعال کردن pan هنگام اتصال
      scaleEnabled: !widget.state.isConnecting,
      onInteractionUpdate: (details) {
        if (details.pointerCount == 1 && !widget.state.isConnecting) {
          // Pan - فقط وقتی که در حال اتصال نیستیم
          widget.state.updateViewport(
            Offset(
              _transformationController.value.getTranslation().x,
              _transformationController.value.getTranslation().y,
            ),
          );
          widget.state.updateZoom(_transformationController.value.getMaxScaleOnAxis());
        }
      },
      child: GestureDetector(
        onPanStart: (details) {
          _lastPanPosition = details.localPosition;
        },
        onPanUpdate: (details) {
          if (widget.state.isConnecting) {
            // تبدیل موقعیت با در نظر گیری transformation
            final canvasPosition = _localToCanvasCoordinates(details.localPosition);
            _connectingToPosition = canvasPosition;
            widget.state.updateConnectingPosition(canvasPosition);
            setState(() {}); // Force rebuild برای نمایش خط
          } else {
            // Pan canvas
            final delta = details.localPosition - (_lastPanPosition ?? Offset.zero);
            _lastPanPosition = details.localPosition;
            // این کار توسط InteractiveViewer انجام می‌شود
          }
        },
        onPanEnd: (details) {
          if (widget.state.isConnecting) {
            // تبدیل موقعیت برای بررسی node
            final canvasPosition = _localToCanvasCoordinates(details.localPosition);
            final droppedNode = _findNodeAtPosition(canvasPosition);
            widget.state.endConnection(droppedNode?.id);
            _connectingToPosition = null;
          }
          _lastPanPosition = null;
          _dragStartPosition = null;
          _draggingNodeId = null;
        },
        onTapUp: (details) {
          // لغو انتخاب
          final canvasPosition = _localToCanvasCoordinates(details.localPosition);
          if (!_isOnNode(canvasPosition)) {
            widget.state.selectNode(null);
            widget.state.selectConnection(null);
          }
        },
        child: Container(
          key: _canvasKey,
          color: Colors.grey.shade50,
          child: Stack(
            children: [
              // Grid background
              RepaintBoundary(
                child: _buildGrid(widget.state.gridSize > 0 ? widget.state.gridSize : WorkflowConstants.gridSize),
              ),
              // Connections (رسم قبل از nodes تا زیر آنها نباشند)
              RepaintBoundary(
                child: CustomPaint(
                  painter: WorkflowConnectionPainter(
                    connections: widget.state.connections,
                    nodePositions: nodePositions,
                    selectedConnectionId: widget.state.selectedConnectionId,
                    isConnecting: widget.state.isConnecting,
                    connectingFrom: connectingFrom,
                    connectingTo: connectingTo,
                  ),
                  size: Size.infinite,
                ),
              ),
              // Nodes (بالاتر از connections)
              ...widget.state.nodes.where((node) {
                // فیلتر کردن نودهایی با موقعیت نامعتبر
                if (!_isValidPosition(node.position)) {
                  debugPrint('نود با موقعیت نامعتبر نادیده گرفته شد: ${node.id}');
                  return false;
                }
                return true;
              }).map((node) {
                try {
                  final isSelected = widget.state.selectedNodeId == node.id;
                  // بررسی اینکه آیا این node قابل اتصال است (برای highlight)
                  final canConnect = _canConnectToNode(node);
                  
                  // اطمینان از اینکه موقعیت معتبر است
                  final validPosition = _isValidPosition(node.position) 
                      ? node.position 
                      : const Offset(200, 200);
                  
                  final nodeToDisplay = node.position != validPosition
                      ? node.copyWith(position: validPosition)
                      : node;
                  
                  return RepaintBoundary(
                    key: ValueKey(node.id),
                    child: WorkflowNodeWidget(
                      node: nodeToDisplay,
                      isSelected: isSelected,
                      zoomLevel: widget.state.zoomLevel > 0 ? widget.state.zoomLevel : 1.0,
                      highlightConnectionPoints: widget.state.isConnecting && canConnect,
                      onTap: () {
                        widget.state.selectNode(node.id);
                        widget.onNodeTap?.call(node);
                      },
                      onLongPress: () {
                        widget.state.selectNode(node.id);
                        if (widget.onNodeLongPress != null) {
                          try {
                            // استفاده از موقعیت node برای نمایش context menu
                            final position = WorkflowConstants.getNodeCenter(validPosition);
                            widget.onNodeLongPress!.call(node, position);
                          } catch (e) {
                            debugPrint('خطا در onLongPress: $e');
                          }
                        }
                      },
                      onDeltaChanged: (globalPosition) {
                        try {
                          // تبدیل global position به canvas coordinates
                          final canvasPosition = _globalToCanvasCoordinates(globalPosition);
                          
                          if (!_isValidPosition(canvasPosition)) {
                            return;
                          }
                          
                          if (_draggingNodeId != node.id) {
                            // شروع drag جدید - ذخیره موقعیت نسبی
                            _draggingNodeId = node.id;
                            // ذخیره موقعیت نسبی (فاصله از گوشه بالا چپ نود)
                            _dragStartPosition = canvasPosition - validPosition;
                          } else if (_dragStartPosition != null) {
                            // محاسبه موقعیت جدید: موقعیت موس منهای فاصله نسبی
                            final newPosition = canvasPosition - _dragStartPosition!;
                            if (_isValidPosition(newPosition)) {
                              widget.state.updateNodePosition(node.id, newPosition);
                            }
                          }
                        } catch (e) {
                          debugPrint('خطا در onDeltaChanged: $e');
                        }
                      },
                      onPositionChanged: (newPosition) {
                        if (_isValidPosition(newPosition)) {
                          widget.state.updateNodePosition(node.id, newPosition);
                        }
                      },
                      onStartConnection: () {
                        widget.state.startConnection(node.id);
                      },
                      onEndConnection: () {
                        widget.state.endConnection(node.id);
                      },
                      onConnectionDragUpdate: (globalPosition) {
                        try {
                          // تبدیل موقعیت global به canvas coordinates
                          final canvasPosition = _globalToCanvasCoordinates(globalPosition);
                          if (_isValidPosition(canvasPosition)) {
                            widget.state.updateConnectingPosition(canvasPosition);
                            setState(() {}); // Force rebuild
                          }
                        } catch (e) {
                          debugPrint('خطا در onConnectionDragUpdate: $e');
                        }
                      },
                    ),
                  );
                } catch (e, stackTrace) {
                  debugPrint('خطا در ساخت widget برای node ${node.id}: $e');
                  debugPrint('StackTrace: $stackTrace');
                  // برگرداندن یک placeholder widget برای جلوگیری از crash
                  return SizedBox(
                    key: ValueKey('error_${node.id}'),
                    width: 0,
                    height: 0,
                  );
                }
              }),
            ],
          ),
        ),
      ),
    );
    } catch (e, stackTrace) {
      debugPrint('خطا در ساخت WorkflowCanvas: $e');
      debugPrint('StackTrace: $stackTrace');
      // برگرداندن یک widget خطا برای جلوگیری از صفحه سفید
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 16),
            Text('خطا در نمایش workflow: ${e.toString()}'),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () {
                setState(() {});
              },
              child: const Text('تلاش مجدد'),
            ),
          ],
        ),
      );
    }
  }

  /// بررسی اعتبار یک موقعیت (نه NaN و نه Infinity)
  bool _isValidPosition(Offset position) {
    return position.dx.isFinite && 
           position.dy.isFinite &&
           !position.dx.isNaN && 
           !position.dy.isNaN;
  }

  Widget _buildGrid(double gridSize) {
    return CustomPaint(
      painter: GridPainter(
        gridSize: gridSize,
        showGrid: true,
      ),
      size: Size.infinite,
    );
  }

  WorkflowNodeModel? _findNodeAtPosition(Offset position) {
    if (!_isValidPosition(position)) {
      return null;
    }
    
    try {
      for (final node in widget.state.nodes) {
        if (!_isValidPosition(node.position)) {
          continue;
        }
        final nodeRect = WorkflowConstants.getNodeRect(node.position);
        if (nodeRect.contains(position)) {
          return node;
        }
      }
    } catch (e) {
      debugPrint('خطا در _findNodeAtPosition: $e');
    }
    return null;
  }

  bool _isOnNode(Offset position) {
    return _findNodeAtPosition(position) != null;
  }

  /// تبدیل موقعیت local (نسبت به InteractiveViewer) به canvas coordinates
  Offset _localToCanvasCoordinates(Offset localPosition) {
    try {
      final matrix = _transformationController.value;
      
      // استفاده از getMaxScaleOnAxis برای دقت بیشتر
      final scale = matrix.getMaxScaleOnAxis();
      final translation = matrix.getTranslation();
      
      // بررسی اعتبار مقادیر
      if (!scale.isFinite || scale.isNaN || scale <= 0) {
        final result = Offset(
          localPosition.dx - (translation.x.isFinite ? translation.x : 0), 
          localPosition.dy - (translation.y.isFinite ? translation.y : 0)
        );
        return _isValidPosition(result) ? result : const Offset(0, 0);
      }
      
      if (!translation.x.isFinite || !translation.y.isFinite || 
          !localPosition.dx.isFinite || !localPosition.dy.isFinite) {
        return const Offset(0, 0);
      }
      
      // تبدیل معکوس: از viewport coordinates به canvas coordinates
      // canvas = (viewport - translation) / scale
      final canvasX = (localPosition.dx - translation.x) / scale;
      final canvasY = (localPosition.dy - translation.y) / scale;
      
      final result = Offset(canvasX, canvasY);
      return _isValidPosition(result) ? result : const Offset(0, 0);
    } catch (e) {
      debugPrint('خطا در _localToCanvasCoordinates: $e');
      return const Offset(0, 0);
    }
  }

  /// تبدیل موقعیت global به canvas coordinates
  Offset _globalToCanvasCoordinates(Offset globalPosition) {
    try {
      if (!_isValidPosition(globalPosition)) {
        return const Offset(0, 0);
      }
      
      // پیدا کردن RenderBox برای InteractiveViewer child (Container)
      final RenderBox? canvasBox = _canvasKey.currentContext?.findRenderObject() as RenderBox?;
      if (canvasBox == null) {
        return const Offset(0, 0);
      }
      
      // تبدیل global به local نسبت به canvas container
      final localPosition = canvasBox.globalToLocal(globalPosition);
      
      if (!_isValidPosition(localPosition)) {
        return const Offset(0, 0);
      }
      
      // سپس تبدیل با transformation matrix
      return _localToCanvasCoordinates(localPosition);
    } catch (e) {
      debugPrint('خطا در _globalToCanvasCoordinates: $e');
      return const Offset(0, 0);
    }
  }

  /// بررسی اینکه آیا می‌توان به یک node اتصال داد
  bool _canConnectToNode(WorkflowNodeModel targetNode) {
    if (!widget.state.isConnecting || widget.state.connectingFromNodeId == null) {
      return false;
    }

    final fromNode = widget.state.getNodeById(widget.state.connectingFromNodeId!);
    if (fromNode == null) return false;

    // نمی‌توان به خود node اتصال داد
    if (fromNode.id == targetNode.id) return false;

    // Trigger نمی‌تواند به trigger دیگر اتصال دهد
    if (fromNode.type == WorkflowNodeType.trigger && targetNode.type == WorkflowNodeType.trigger) {
      return false;
    }

    // اگر قبلاً این connection وجود داشته باشد، قابل اتصال نیست
    final exists = widget.state.connections.any(
      (c) => c.sourceNodeId == fromNode.id && c.targetNodeId == targetNode.id,
    );

    return !exists;
  }
}

/// Painter برای رسم grid در پس‌زمینه
class GridPainter extends CustomPainter {
  final double gridSize;
  final bool showGrid;

  GridPainter({
    this.gridSize = 20.0,
    this.showGrid = true,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (!showGrid || gridSize <= 0) return;

    final paint = Paint()
      ..color = Colors.grey.shade300
      ..strokeWidth = 0.5;

    // خطوط عمودی
    for (double x = 0; x < size.width; x += gridSize) {
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        paint,
      );
    }

    // خطوط افقی
    for (double y = 0; y < size.height; y += gridSize) {
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(GridPainter oldDelegate) {
    return oldDelegate.gridSize != gridSize || oldDelegate.showGrid != showGrid;
  }
}


